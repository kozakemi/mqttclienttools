import SwiftUI
import MQTTClient

struct Message: Identifiable, Codable {
    let id = UUID()
    let content: String
    let isReceived: Bool
    let timestamp: Date
    let qosLevel: Int // 0, 1, 或 2
    
    init(content: String, isReceived: Bool, timestamp: Date, qosLevel: Int = 1) {
        self.content = content
        self.isReceived = isReceived
        self.timestamp = timestamp
        self.qosLevel = qosLevel
    }
}

class Topic: Identifiable, Codable {
    var id = UUID()
    var name: String
    var messages: [Message] = []
    
    init(name: String, messages: [Message] = []) {
        self.name = name
        self.messages = messages
    }
    
    // 添加编解码所需的方法
    enum CodingKeys: String, CodingKey {
        case id, name, messages
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        messages = try container.decode([Message].self, forKey: .messages)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(messages, forKey: .messages)
    }
}

class HomwViewModel: NSObject, ObservableObject {
    // QoS级别枚举
    enum QoSLevel: Int, CaseIterable, Identifiable {
        case atMostOnce = 0
        case atLeastOnce = 1
        case exactlyOnce = 2
        
        var id: Int { self.rawValue }
        
        var description: String {
            switch self {
            case .atMostOnce: return "QoS 0"
            case .atLeastOnce: return "QoS 1"
            case .exactlyOnce: return "QoS 2"
            }
        }
        
        var mqttQoS: MQTTQosLevel {
            switch self {
            case .atMostOnce:
                print("发送使用QoS 0，值为\(MQTTQosLevel.atMostOnce.rawValue)")
                return .atMostOnce
            case .atLeastOnce:
                print("发送使用QoS 1，值为\(MQTTQosLevel.atLeastOnce.rawValue)")
                return .atLeastOnce
            case .exactlyOnce:
                print("发送使用QoS 2，值为\(MQTTQosLevel.exactlyOnce.rawValue)")
                return .exactlyOnce
            }
        }
        
        // 从MQTTQosLevel创建QoSLevel的静态方法
        static func from(mqttQoS: MQTTQosLevel) -> QoSLevel {
            switch mqttQoS {
            case .atMostOnce:
                return .atMostOnce
            case .atLeastOnce:
                return .atLeastOnce
            case .exactlyOnce:
                return .exactlyOnce
            @unknown default:
                print("未知QoS级别，默认使用QoS 1")
                return .atLeastOnce
            }
        }
    }
    
    @Published var isConnected = false
    @Published var selectedQoS: QoSLevel = .atLeastOnce
    
    // 警告系统
    enum AlertType: Identifiable {
        case connection(message: String)
        case clearConfirm(topic: Topic)
        case deleteTopic(topic: Topic)
        
        var id: String {
            switch self {
            case .connection: return "connection"
            case .clearConfirm(let topic): return "clear_\(topic.id)"
            case .deleteTopic(let topic): return "delete_\(topic.id)"
            }
        }
    }
    
    @Published var alertType: AlertType? = nil
    
    @Published var showSidebar = false
    @Published var topics: [Topic] = []
    @Published var newTopic = ""
    @Published var selectedTopic: Topic? {
        didSet {
            if selectedTopic == nil { return }
        }
    }
    @Published var messageText = ""
    private let defaults = UserDefaults.standard
    private var transport: MQTTCFSocketTransport?
    private var session: MQTTSession?
    
    override init() {
        super.init()
        loadTopics()
        
        // 加载上次使用的QoS级别
        if let savedQoS = defaults.object(forKey: "selectedQoS") as? Int,
           let qos = QoSLevel(rawValue: savedQoS) {
            selectedQoS = qos
        }
    }
    
    private func loadTopics() {
        if let data = defaults.data(forKey: "savedTopics"),
           let decodedTopics = try? JSONDecoder().decode([Topic].self, from: data) {
            topics = decodedTopics
        }
    }
    
    func saveTopics() {
        if let encoded = try? JSONEncoder().encode(topics) {
            defaults.set(encoded, forKey: "savedTopics")
        }
    }
    
    func clearMessages(for topicId: UUID) {
        print("开始清除消息，topicId: \(topicId)")
        
        guard let index = topics.firstIndex(where: { $0.id == topicId }) else {
            print("未找到对应的topic，topicId: \(topicId)")
            return
        }
        
        print("找到topic索引: \(index)，消息数量: \(topics[index].messages.count)")
        
        // 直接清空消息 - 因为Topic现在是class，所以这个改变会直接影响所有引用
        topics[index].messages.removeAll()
        
        print("消息已清空，当前消息数量: \(topics[index].messages.count)")
        
        // 保存更新后的数据
        saveTopics()
        print("已保存topics到UserDefaults")
        
        // 通知UI刷新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 发送变化通知
            self.objectWillChange.send()
            print("已发送UI更新通知")
        }
    }
    
    func connectMQTT() {
        guard let ipAddress = defaults.string(forKey: "ipAddress"),
              let port = defaults.value(forKey: "port") as? Int,
              let clientId = defaults.string(forKey: "clientId") else {
            showAlert("请先在配置页面设置MQTT连接信息")
            isConnected = false
            return
        }
        
        // 检查IP地址和端口是否有效
        if ipAddress.isEmpty {
            showAlert("IP地址不能为空")
            isConnected = false
            return
        }
        
        transport = MQTTCFSocketTransport()
        transport?.host = ipAddress
        transport?.port = UInt32(port)
        
        session = MQTTSession()
        session?.transport = transport
        session?.clientId = clientId
        
        if let username = defaults.string(forKey: "username") {
            session?.userName = username
        }
        if let password = defaults.string(forKey: "password") {
            session?.password = password
        }
        
        // 设置连接超时检测
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if !self.isConnected {
                print("MQTT连接超时")
                self.showAlert("连接超时，请检查配置信息和网络状态")
                self.isConnected = false
            }
        }
        
        print("正在尝试连接MQTT服务器: \(ipAddress):\(port)")
        session?.connect()
        session?.delegate = self
    }
    
    func disconnectMQTT() {
        session?.disconnect()
        session = nil
        transport = nil
        isConnected = false
    }
    
    func sendMessage(_ content: String, to topic: String) {
        guard !content.isEmpty else {
            showAlert("消息内容不能为空")
            return
        }
        
        guard isConnected else {
            showAlert("MQTT未连接，请先连接MQTT服务器")
            return
        }
        
        guard let session = session else { return }
        session.publishData(content.data(using: .utf8), 
                           onTopic: topic, 
                           retain: false, 
                           qos: selectedQoS.mqttQoS)
        
        if let index = topics.firstIndex(where: { $0.name == topic }) {
            let message = Message(content: content, 
                                 isReceived: false, 
                                 timestamp: Date(), 
                                 qosLevel: selectedQoS.rawValue)
            topics[index].messages.append(message)
            if selectedTopic?.name == topic {
                selectedTopic = topics[index]
            }
            saveTopics()
        }
        
        // 保存选择的QoS级别供下次使用
        defaults.set(selectedQoS.rawValue, forKey: "selectedQoS")
    }
    
    // 添加删除Topic的方法
    func deleteTopic(_ topic: Topic) {
        // 如果当前选中的topic就是要删除的topic，先将selectedTopic置为nil
        if selectedTopic?.id == topic.id {
            selectedTopic = nil
        }
        
        // 从topics数组中移除该topic
        topics.removeAll(where: { $0.id == topic.id })
        
        // 保存更新后的topics
        saveTopics()
        
        // 通知UI刷新
        objectWillChange.send()
    }
    
    func showAlert(_ message: String) {
        alertType = .connection(message: message)
    }
}

extension HomwViewModel: MQTTSessionDelegate {
    func handleEvent(_ session: MQTTSession!, event: MQTTSessionEvent, error: Error!) {
        print("MQTT事件: \(event.rawValue), 错误: \(error?.localizedDescription ?? "无")")
        
        DispatchQueue.main.async {
            switch event {
            case .connected:
                self.isConnected = true
                print("MQTT连接成功")
                // 连接成功后订阅所有Topic
                for topic in self.topics {
                    let qosLevel = self.selectedQoS.mqttQoS
                    session.subscribe(toTopic: topic.name, at: qosLevel)
                    print("已订阅Topic: \(topic.name)，使用QoS级别: \(self.selectedQoS.rawValue)")
                }
            case .connectionClosed:
                self.isConnected = false
                self.showAlert("MQTT连接已关闭")
                print("MQTT连接关闭")
            case .connectionError:
                self.isConnected = false
                self.showAlert("MQTT连接错误: \(error?.localizedDescription ?? "未知错误")")
                print("MQTT连接错误: \(error?.localizedDescription ?? "未知错误")")
            case .connectionRefused:
                self.isConnected = false
                self.showAlert("MQTT连接被拒绝")
                print("MQTT连接被拒绝")
            default:
                print("其他MQTT事件: \(event.rawValue)")
                break
            }
        }
    }
    
    func newMessage(_ session: MQTTSession!, data: Data!, onTopic topic: String!, qos: MQTTQosLevel, retained: Bool, mid: UInt32) {
        guard let content = String(data: data, encoding: .utf8) else { return }
        
        // 检查是否是自己发送的消息
        if let lastMessage = topics.first(where: { $0.name == topic })?.messages.last,
           lastMessage.content == content && !lastMessage.isReceived {
            return // 如果是自己刚发送的消息，则不重复显示
        }
        
        // 输出接收到的原始QoS值，用于调试
        print("接收到消息，原始QoS原始值: \(qos.rawValue)")
        
        // 将MQTTQosLevel转换为Int
        // MQTTClient库中的定义是：
        // MQTTQosLevelAtMostOnce = 0
        // MQTTQosLevelAtLeastOnce = 1
        // MQTTQosLevelExactlyOnce = 2
        let qosInt: Int
        
        // 使用rawValue直接获取QoS级别
        qosInt = Int(qos.rawValue)
        print("接收消息使用QoS级别: \(qosInt)")
        
        DispatchQueue.main.async {
            if let index = self.topics.firstIndex(where: { $0.name == topic }) {
                // 使用转换后的QoS级别
                let message = Message(content: content, 
                                     isReceived: true, 
                                     timestamp: Date(), 
                                     qosLevel: qosInt)
                
                self.topics[index].messages.append(message)
                if self.selectedTopic?.name == topic {
                    self.selectedTopic = self.topics[index]
                }
                self.saveTopics()
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        VStack(alignment: message.isReceived ? .leading : .trailing) {
            // 添加QoS级别标签
            HStack {
                if !message.isReceived {
                    Spacer()
                }
                
                let qosString = String(format: "QoS %d", message.qosLevel)
                Text(qosString)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                
                if message.isReceived {
                    Spacer()
                }
            }
            
            // 消息内容
            HStack {
                if !message.isReceived {
                    Spacer()
                }
                Text(message.content)
                    .padding(10)
                    .background(message.isReceived ? Color.gray.opacity(0.2) : Color.blue.opacity(0.2))
                    .cornerRadius(10)
                if message.isReceived {
                    Spacer()
                }
            }
        }
    }
}

struct ChatView: View {
    @ObservedObject var viewModel: HomwViewModel
    let topic: Topic
    let onClearRequest: (Topic) -> Void
    @State private var scrollToBottom = false
    @State private var scrollToTop = false
    @State private var messageCount: Int = 0  // 用于强制刷新视图
    
    var body: some View {
        VStack {
            // 顶部工具栏
            HStack(spacing: 20) {
                Button(action: {
                    scrollToTop = true
                }) {
                    HStack {
                        Image(systemName: "arrow.up")
                        Text("顶部")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                Button(action: {
                    scrollToBottom = true
                }) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("底部")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Button(action: {
                    print("清空按钮被点击")
                    onClearRequest(topic)  // 使用回调
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清空")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // 聊天内容
            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(topic.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id) // 为每个消息设置ID，用于滚动定位
                        }
                        // 底部锚点
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: topic.messages.count) { _ in
                    // 当消息数量变化时，自动滚动到底部
                    withAnimation {
                        scrollView.scrollTo("bottom")
                    }
                }
                .onChange(of: scrollToBottom) { newValue in
                    if newValue {
                        withAnimation {
                            scrollView.scrollTo("bottom")
                        }
                        scrollToBottom = false
                    }
                }
                .onChange(of: scrollToTop) { newValue in
                    if newValue && !topic.messages.isEmpty {
                        withAnimation {
                            scrollView.scrollTo(topic.messages.first!.id)
                        }
                        scrollToTop = false
                    }
                }
                // 添加一个对messageCount变化的监听，强制刷新视图
                .id(messageCount)
            }
            
            // QoS选择器
            HStack {
                Text("发送QoS:")
                    .font(.system(size: 14))
                
                Picker("QoS级别", selection: $viewModel.selectedQoS) {
                    ForEach(HomwViewModel.QoSLevel.allCases) { qos in
                        Text(qos.description).tag(qos)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
            }
            .padding(.horizontal)
            
            // 输入框
            HStack {
                TextField("输入消息", text: $viewModel.messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button(action: {
                    if !viewModel.messageText.isEmpty {
                        viewModel.sendMessage(viewModel.messageText, to: topic.name)
                        if viewModel.isConnected { // 只有在连接状态下才清空输入框
                            viewModel.messageText = ""
                            // 发送消息后设置滚动标志
                            scrollToBottom = true
                        }
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .padding(.trailing)
            }
            .padding(.vertical)
        }
        // 在视图出现时记录当前消息数
        .onAppear {
            messageCount = topic.messages.count
            print("ChatView appeared，消息数量: \(messageCount)")
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: HomwViewModel
    
    var body: some View {
        VStack {
            // Topic列表
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.topics) { topic in
                        HStack {
                            Button(action: {
                                viewModel.selectedTopic = topic
                            }) {
                                Text(topic.name)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(viewModel.selectedTopic?.id == topic.id ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                viewModel.alertType = .deleteTopic(topic: topic)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .padding(.trailing, 8)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // 添加Topic的输入框
            HStack {
                TextField("输入新Topic", text: $viewModel.newTopic)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button(action: {
                    if !viewModel.newTopic.isEmpty {
                        let newTopic = Topic(name: viewModel.newTopic)
                        viewModel.topics.append(newTopic)
                        viewModel.newTopic = ""
                        viewModel.saveTopics()
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .padding(.trailing)
            }
            .padding(.vertical)
            
            Spacer()
            
            // 底部的关于我按钮
            NavigationLink(destination: AboutMeView()) {
                HStack {
                    Image(systemName: "person.circle")
                    Text("关于我")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
            .padding()
        }
        .frame(width: 250)
        .background(Color(.systemBackground))
    }
}

struct HomwView: View {
    @ObservedObject var viewModel: HomwViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        NavigationView {
            VStack {
                if let selectedTopic = viewModel.selectedTopic {
                    ChatView(
                        viewModel: viewModel, 
                        topic: selectedTopic,
                        onClearRequest: { topic in
                            viewModel.alertType = .clearConfirm(topic: topic)
                        }
                    )
                } else {
                    HStack {
                        Text(viewModel.isConnected ? "已连接" : "未连接")
                            .foregroundColor(viewModel.isConnected ? .green : .red)
                    }
                    .padding()
                    Text("请选择一个Topic开始聊天")
                        .foregroundColor(.gray)
                }
            }
            .navigationBarTitle(viewModel.selectedTopic?.name ?? "主页", displayMode: .inline)
            .navigationBarItems(
                trailing: Toggle(isOn: $viewModel.isConnected) {
                    Text("连接")
                }
                .onChange(of: viewModel.isConnected) { newValue in
                    if newValue {
                        viewModel.connectMQTT()
                    } else {
                        viewModel.disconnectMQTT()
                    }
                }
            )
            
            // 确保iPad上有默认内容（这个视图在iPad分屏模式下会显示）
            Text("请在主页查看内容")
                .font(.title)
                .foregroundColor(.gray)
        }
        // 使用StackNavigationViewStyle确保在所有设备上使用单一视图
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    HomwView(viewModel: HomwViewModel())
}


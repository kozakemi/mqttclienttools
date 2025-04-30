import SwiftUI
import MQTTClient

struct Message: Identifiable, Codable {
    let id = UUID()
    let content: String
    let isReceived: Bool
    let timestamp: Date
}

struct Topic: Identifiable, Codable {
    let id = UUID()
    var name: String
    var messages: [Message]
}

class HomwViewModel: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var showAlert = false
    @Published var alertMessage = ""
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
    
    func connectMQTT() {
        guard let ipAddress = defaults.string(forKey: "ipAddress"),
              let port = defaults.value(forKey: "port") as? Int,
              let clientId = defaults.string(forKey: "clientId") else {
            alertMessage = "请先在配置页面设置MQTT连接信息"
            showAlert = true
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
                self.alertMessage = "连接超时，请检查配置信息和网络状态"
                self.showAlert = true
                self.isConnected = false
            }
        }
        
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
        guard let session = session, isConnected else { return }
        session.publishData(content.data(using: .utf8), onTopic: topic, retain: false, qos: .atLeastOnce)
        
        if let index = topics.firstIndex(where: { $0.name == topic }) {
            let message = Message(content: content, isReceived: false, timestamp: Date())
            topics[index].messages.append(message)
            if selectedTopic?.name == topic {
                selectedTopic = topics[index]
            }
            saveTopics()
        }
    }
}

extension HomwViewModel: MQTTSessionDelegate {
    func handleEvent(_ session: MQTTSession!, event: MQTTSessionEvent, error: Error!) {
        DispatchQueue.main.async {
            switch event {
            case .connected:
                self.isConnected = true
                // 连接成功后订阅所有Topic
                for topic in self.topics {
                    session.subscribe(toTopic: topic.name, at: .atLeastOnce)
                }
            case .connectionClosed, .connectionError, .connectionRefused:
                self.isConnected = false
                self.alertMessage = "MQTT连接失败"
                self.showAlert = true
            default:
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
        
        DispatchQueue.main.async {
            if let index = self.topics.firstIndex(where: { $0.name == topic }) {
                let message = Message(content: content, isReceived: true, timestamp: Date())
                self.topics[index].messages.append(message)
                if self.selectedTopic?.name == topic {
                    self.selectedTopic = self.topics[index]
                }
                self.saveTopics()
            }
        }
    }
}

struct ChatView: View {
    @ObservedObject var viewModel: HomwViewModel
    let topic: Topic
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(topic.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            
            HStack {
                TextField("输入消息", text: $viewModel.messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button(action: {
                    if !viewModel.messageText.isEmpty {
                        viewModel.sendMessage(viewModel.messageText, to: topic.name)
                        viewModel.messageText = ""
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .padding(.trailing)
            }
            .padding(.vertical)
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
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

struct SidebarView: View {
    @ObservedObject var viewModel: HomwViewModel
    
    var body: some View {
        VStack {
            // Topic列表
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.topics) { topic in
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
                        viewModel.topics.append(Topic(name: viewModel.newTopic, messages: []))
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
    
    var body: some View {
        NavigationView {
            VStack {
                if let selectedTopic = viewModel.selectedTopic {
                    ChatView(viewModel: viewModel, topic: selectedTopic)
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
            .alert(isPresented: $viewModel.showAlert) {
                Alert(
                    title: Text("连接提示"),
                    message: Text(viewModel.alertMessage),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
    }
}

#Preview {
    HomwView(viewModel: HomwViewModel())
}


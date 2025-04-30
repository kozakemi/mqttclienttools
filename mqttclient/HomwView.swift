import SwiftUI
import MQTTClient

struct Message: Identifiable, Codable {
    let id = UUID()
    let content: String
    let isReceived: Bool
    let timestamp: Date
    let qosLevel: Int // 0, 1, 或 2
    let format: String
    
    init(content: String, isReceived: Bool, timestamp: Date, qosLevel: Int = 1, format: String) {
        self.content = content
        self.isReceived = isReceived
        self.timestamp = timestamp
        self.qosLevel = qosLevel
        self.format = format
    }
    
    // 添加一个便捷的初始化方法，接受MessageFormat枚举
    init(content: String, isReceived: Bool, timestamp: Date, qosLevel: Int = 1, format: MessageFormat) {
        self.content = content
        self.isReceived = isReceived
        self.timestamp = timestamp
        self.qosLevel = qosLevel
        self.format = format.rawValue
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

// 消息格式枚举
enum MessageFormat: String, CaseIterable, Identifiable {
    case text = "文本"
    case hex = "十六进制"
    case json = "JSON"
    
    var id: Self { self }
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
    @Published var isConnecting = false  // 添加连接中状态标志
    @Published var selectedQoS: QoSLevel = .atLeastOnce
    @Published var selectedFormat: MessageFormat = .text
    private var alertMessage: String = ""
    @Published var ignoreOwnMessages = true // 是否忽略自己发送的消息
    // 储存最近发送的消息，用于去重
    private var recentlySentMessages: [(topic: String, message: String, timestamp: Date)] = []
    private let recentMessageTimeout: TimeInterval = 2.0 // 2秒内认为是自己发送的消息
    
    // 添加消息队列和队列处理锁
    private var messageQueue: [(String, Topic)] = []
    private var processingMessages = false
    private var savingTopics = false
    
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
        
        // 加载上次使用的消息格式
        if let savedFormat = defaults.string(forKey: "selectedFormat"),
           let format = MessageFormat(rawValue: savedFormat) {
            selectedFormat = format
        }
        
        // 加载是否忽略自己发送的消息设置
        ignoreOwnMessages = defaults.bool(forKey: "ignoreOwnMessages")
    }
    
    private func loadTopics() {
        if let data = defaults.data(forKey: "savedTopics"),
           let decodedTopics = try? JSONDecoder().decode([Topic].self, from: data) {
            topics = decodedTopics
        }
    }
    
    func saveTopics() {
        // 限制每个主题的消息数量，避免过多消息导致性能问题
        let maxMessagesPerTopic = 500
        
        // 在保存前检查是否有主题消息数量超过限制
        for (index, topic) in topics.enumerated() {
            if topic.messages.count > maxMessagesPerTopic {
                // 保留最近的maxMessagesPerTopic条消息
                print("主题 \(topic.name) 消息数量 \(topic.messages.count) 超过限制，将裁剪为 \(maxMessagesPerTopic) 条")
                topics[index].messages = Array(topic.messages.suffix(maxMessagesPerTopic))
            }
        }
        
        // 批量编码和保存，避免频繁操作UserDefaults
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
        // 防止重复连接
        if isConnecting {
            print("MQTT连接已在进行中，避免重复连接")
            return
        }
        
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
        
        // 设置连接中状态
        isConnecting = true
        
        // 在后台线程处理连接过程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.transport = MQTTCFSocketTransport()
            self.transport?.host = ipAddress
            self.transport?.port = UInt32(port)
            
            self.session = MQTTSession()
            self.session?.transport = self.transport
            self.session?.clientId = clientId
            
            if let username = self.defaults.string(forKey: "username") {
                self.session?.userName = username
            }
            if let password = self.defaults.string(forKey: "password") {
                self.session?.password = password
            }
            
            // 设置连接超时检测
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                if self.isConnecting && !self.isConnected {
                    print("MQTT连接超时")
                    self.showAlert("连接超时，请检查配置信息和网络状态")
                    self.isConnected = false
                    self.isConnecting = false
                }
            }
            
            print("正在尝试连接MQTT服务器: \(ipAddress):\(port)")
            
            // 设置delegate和连接
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.session?.delegate = self
                self.session?.connect()
            }
        }
    }
    
    func disconnectMQTT() {
        isConnected = false
        isConnecting = false
        
        // 在后台线程处理断开连接，避免阻塞UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session?.disconnect()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.session = nil
                self.transport = nil
            }
        }
    }
    
    // 准备要发送的数据
    func prepareMessageData(content: String, format: MessageFormat) -> Data? {
        switch format {
        case .text:
            return content.data(using: .utf8)
            
        case .hex:
            // 转换十六进制字符串为数据
            // 先移除所有空格
            let hexString = content.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: ",", with: "")
            
            var data = Data()
            
            // 解析十六进制字符串
            var formattedHex = ""
            let characters = Array(hexString)
            
            // 每两个字符一组，转为一个字节
            var i = 0
            while i < characters.count {
                var byteString = ""
                
                if i + 1 < characters.count {
                    byteString = String(characters[i...i+1])
                    i += 2
                } else {
                    byteString = String(characters[i]) + "0"
                    i += 1
                }
                
                if let byte = UInt8(byteString, radix: 16) {
                    data.append(byte)
                    formattedHex += byteString + " "
                } else {
                    alertMessage = "无效的十六进制字符串"
                    return nil
                }
            }
            
            print("解析十六进制: \(formattedHex.trimmingCharacters(in: .whitespaces))")
            return data
            
        case .json:
            // 验证是否是有效的JSON字符串
            do {
                // 尝试解析为JSON
                if let jsonData = content.data(using: .utf8),
                   let _ = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                    return jsonData
                } else {
                    alertMessage = "无效的JSON格式"
                    return nil
                }
            } catch {
                alertMessage = "JSON解析错误: \(error.localizedDescription)"
                return nil
            }
        }
    }
    
    func sendMessage(_ content: String, to topic: Topic) {
        // 处理大消息前先确认
        if content.count > 5000 {
            print("警告：消息内容过长，可能影响性能")
        }
        
        // 添加到队列
        addMessageToQueue(content, topic)
    }
    
    // 添加消息队列处理方法
    private func addMessageToQueue(_ content: String, _ topic: Topic) {
        // 添加到队列
        messageQueue.append((content, topic))
        
        // 如果不在处理中，则开始处理
        if !processingMessages {
            processMessageQueue()
        }
    }
    
    // 处理消息队列
    private func processMessageQueue() {
        // 设置处理标志
        processingMessages = true
        
        // 如果队列为空，则完成处理
        if messageQueue.isEmpty {
            processingMessages = false
            return
        }
        
        // 获取队列中第一个消息
        let (content, topic) = messageQueue.removeFirst()
        
        // 在后台线程处理消息发送
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 准备消息数据
            guard let data = self.prepareMessageData(content: content, format: self.selectedFormat) else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.showAlert("无法准备消息数据")
                    // 继续处理队列中的下一个消息
                    self.processMessageQueue()
                }
                return
            }
            
            // 检查连接状态
            guard self.isConnected else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.showAlert("MQTT未连接，请先连接MQTT服务器")
                    // 继续处理队列中的下一个消息
                    self.processMessageQueue()
                }
                return
            }
            
            guard let session = self.session else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.showAlert("MQTT会话未创建")
                    // 继续处理队列中的下一个消息
                    self.processMessageQueue()
                }
                return
            }
            
            // 发布MQTT消息
            session.publishData(data, 
                               onTopic: topic.name, 
                               retain: false, 
                               qos: self.selectedQoS.mqttQoS)
            
            // 在主线程更新UI和状态
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 添加到消息列表
                let newMessage = Message(content: content, 
                                        isReceived: false, 
                                        timestamp: Date(), 
                                        qosLevel: self.selectedQoS.rawValue, 
                                        format: self.selectedFormat)
                
                // 添加消息到topic
                if let index = self.topics.firstIndex(where: { $0.id == topic.id }) {
                    self.topics[index].messages.append(newMessage)
                    
                    // 如果是当前选中的topic，更新引用
                    if self.selectedTopic?.id == topic.id {
                        self.selectedTopic = self.topics[index]
                    }
                    
                    // 记录此消息到最近发送的消息列表，以便可以忽略自己的消息
                    if self.ignoreOwnMessages {
                        self.addRecentlySentMessage(topic: topic.name, message: content)
                    }
                    
                    // 保存QoS级别和格式偏好
                    self.defaults.set(self.selectedQoS.rawValue, forKey: "selectedQoS")
                    self.defaults.set(self.selectedFormat.rawValue, forKey: "selectedFormat")
                    
                    // 延迟保存，避免频繁IO
                    if !self.savingTopics {
                        self.savingTopics = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            guard let self = self else { return }
                            self.saveTopics()
                            self.savingTopics = false
                        }
                    }
                }
                
                print("消息已发送到Topic: \(topic.name), 格式: \(self.selectedFormat.rawValue)")
                
                // 继续处理队列中的下一个消息
                self.processMessageQueue()
            }
        }
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
    
    // 提供获取当前会话的方法，供外部使用
    func getSession() -> MQTTSession? {
        return session
    }
    
    // 添加最近发送的消息到列表
    private func addRecentlySentMessage(topic: String, message: String) {
        let newEntry = (topic: topic, message: message, timestamp: Date())
        recentlySentMessages.append(newEntry)
        
        // 清理超过超时时间的旧消息
        cleanupOldSentMessages()
    }
    
    // 检查消息是否是最近自己发送的
    private func isRecentlySentMessage(topic: String, message: String) -> Bool {
        cleanupOldSentMessages() // 先清理过期消息
        
        return recentlySentMessages.contains { entry in
            return entry.topic == topic && entry.message == message
        }
    }
    
    // 清理超时的消息记录
    private func cleanupOldSentMessages() {
        let now = Date()
        recentlySentMessages = recentlySentMessages.filter { entry in
            return now.timeIntervalSince(entry.timestamp) < recentMessageTimeout
        }
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
                    session.subscribe(toTopic: topic.name, at: qosLevel, subscribeHandler: { error, gQoss in
                        if let error = error {
                            print("订阅Topic失败: \(topic.name), 错误: \(error.localizedDescription)")
                            self.showAlert("订阅失败: \(error.localizedDescription)")
                        } else {
                            print("成功订阅Topic: \(topic.name), QoS: \(gQoss?.first?.intValue ?? -1)")
                        }
                    })
                    print("已请求订阅Topic: \(topic.name)，使用QoS级别: \(self.selectedQoS.rawValue)")
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
        // 将MQTTQosLevel转换为Int
        let qosInt = Int(qos.rawValue)
        print("接收消息使用QoS级别: \(qosInt)")
        
        // 基本检查，避免处理无效数据
        guard data.count > 0 else {
            print("收到空数据，忽略")
            return
        }
        
        // 为大数据消息设置处理限制
        let maxDataSize = 1024 * 10 // 10KB
        if data.count > maxDataSize {
            print("收到大数据消息：\(data.count) 字节，可能需要特殊处理")
            // 可以在这里添加大数据处理逻辑
        }
        
        // 尝试以不同格式解析收到的数据
        var content = ""
        var detectedFormat = MessageFormat.text
        var isValidData = true
        
        // 首先尝试作为UTF-8文本解析
        if let textContent = String(data: data, encoding: .utf8) {
            content = textContent
            
            // 如果设置了忽略自己发送的消息，检查是否是自己发送的
            if ignoreOwnMessages && isRecentlySentMessage(topic: topic, message: content) {
                print("忽略自己发送的消息: \(content)")
                return // 忽略自己发送的消息
            }
            
            // 检测是否为JSON格式
            if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") &&
               content.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}") {
                if let _ = try? JSONSerialization.jsonObject(with: data, options: []) {
                    detectedFormat = .json
                }
            }
            // 检测是否为十六进制格式
            else if content.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "0x", with: "")
                .allSatisfy({ $0.isHexDigit }) {
                detectedFormat = .hex
            }
        } else {
            // 如果不是文本，则尝试将其作为二进制数据，并转换为十六进制字符串
            content = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            detectedFormat = .hex
            print("接收到二进制数据，转换为十六进制: \(content)")
            
            // 对于二进制数据，也需要检查是否忽略自己发送的消息
            if ignoreOwnMessages && isRecentlySentMessage(topic: topic, message: content) {
                print("忽略自己发送的二进制消息")
                return
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 检查主题是否已存在
            if let index = self.topics.firstIndex(where: { $0.name == topic }) {
                if isValidData {
                    // 获取当前主题的消息数量
                    let currentCount = self.topics[index].messages.count
                    
                    // 如果消息数量过多，进行优化处理
                    let maxMessagesInMemory = 500
                    if currentCount > maxMessagesInMemory {
                        // 仅保留较新的消息
                        print("主题 \(topic) 的消息数量过多，进行优化")
                        let messagesToKeep = Array(self.topics[index].messages.suffix(maxMessagesInMemory - 1))
                        self.topics[index].messages = messagesToKeep
                    }
                    
                    // 使用检测到的格式或默认文本格式
                    let message = Message(content: content, 
                                       isReceived: true, 
                                       timestamp: Date(), 
                                       qosLevel: qosInt,
                                       format: detectedFormat)
                    
                    // 添加新消息
                    self.topics[index].messages.append(message)
                    
                    // 更新选中的主题，以便刷新UI
                    if self.selectedTopic?.name == topic {
                        self.selectedTopic = self.topics[index]
                    }
                    
                    // 延迟保存，减少频繁写入
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.saveTopics()
                    }
                    
                    print("已保存接收到的消息: \(content) (格式: \(detectedFormat.rawValue))")
                } else {
                    print("接收到无效数据，无法解析")
                }
            } else {
                // 如果主题不存在，创建一个新主题
                print("发现新主题: \(topic)，自动创建")
                let newTopic = Topic(name: topic)
                let message = Message(content: content,
                                   isReceived: true,
                                   timestamp: Date(),
                                   qosLevel: qosInt,
                                   format: detectedFormat)
                newTopic.messages.append(message)
                self.topics.append(newTopic)
                
                // 保存新主题
                self.saveTopics()
                
                // 如果启用了自动订阅，对这个新主题进行订阅
                if self.session?.status == .connected {
                    let qosLevel = self.selectedQoS.mqttQoS
                    self.session?.subscribe(toTopic: topic, at: qosLevel, subscribeHandler: { error, gQoss in
                        if let error = error {
                            print("自动订阅新主题失败: \(topic), 错误: \(error.localizedDescription)")
                        } else {
                            print("自动订阅新主题成功: \(topic)")
                        }
                    })
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    @State private var showCopyAlert = false
    @State private var isExpanded = false
    
    // 计算要显示的消息内容
    private var displayContent: String {
        if message.content.count <= 500 || isExpanded {
            return message.content
        } else {
            return String(message.content.prefix(500)) + "... (点击查看更多)"
        }
    }
    
    var body: some View {
        VStack(alignment: message.isReceived ? .leading : .trailing) {
            // 顶部信息栏：QoS级别和格式
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
                
                // 显示消息格式
                Text(message.format)
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
                
                // 使用LazyText来显示文本
                Text(displayContent)
                    .padding(10)
                    .background(message.isReceived ? Color.gray.opacity(0.2) : Color.blue.opacity(0.2))
                    .cornerRadius(10)
                    // 添加可选择文本支持
                    .textSelection(.enabled)
                    // 点击展开长消息
                    .onTapGesture {
                        if message.content.count > 500 && !isExpanded {
                            isExpanded = true
                        }
                    }
                    // 添加长按菜单
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                            showCopyAlert = true
                        }) {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }
                
                if message.isReceived {
                    Spacer()
                }
            }
        }
        // 添加复制成功的提示
        .alert("已复制到剪贴板", isPresented: $showCopyAlert) {
            Button("确定", role: .cancel) { }
        }
    }
}

struct ChatView: View {
    @ObservedObject var viewModel: HomwViewModel
    let topic: Topic
    let onClearRequest: (Topic) -> Void
    @State private var scrollToBottom = false
    @State private var scrollToTop = false
    @State private var messageCount: Int = 0
    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var showCopiedAlert = false
    
    // 添加分页状态
    @State private var currentPage: Int = 1
    @State private var messagesPerPage: Int = 30
    @State private var showLoadMoreButton = false
    
    // 添加本地输入状态变量，避免直接使用ViewModel中的状态
    @State private var localMessageText: String = ""
    @FocusState private var isInputFocused: Bool
    
    // 计算当前要显示的消息
    private var displayedMessages: [Message] {
        let totalMessages = topic.messages
        if totalMessages.count <= messagesPerPage {
            return totalMessages
        } else {
            // 如果消息过多则只显示最新的messagesPerPage条
            let startIndex = max(0, totalMessages.count - (currentPage * messagesPerPage))
            return Array(totalMessages.suffix(currentPage * messagesPerPage))
        }
    }
    
    // 添加隐藏键盘的方法
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    var body: some View {
        VStack {
            // 顶部工具栏
            HStack(spacing: 16) {
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
            
            // 添加加载更多按钮（在顶部）
            if showLoadMoreButton && topic.messages.count > messagesPerPage && currentPage * messagesPerPage < topic.messages.count {
                Button(action: {
                    currentPage += 1
                }) {
                    Text("加载更多历史消息...")
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                }
            }
            
            // 聊天内容 - 添加点击事件隐藏键盘
            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(displayedMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id) // 为每个消息设置ID，用于滚动定位
                        }
                        // 底部锚点
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .simultaneousGesture(
                    TapGesture().onEnded { _ in
                        // 点击消息区域时，隐藏键盘
                        hideKeyboard()
                    }
                )
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
                    if newValue && !displayedMessages.isEmpty {
                        withAnimation {
                            scrollView.scrollTo(displayedMessages.first!.id)
                        }
                        scrollToTop = false
                    }
                }
                // 添加一个对messageCount变化的监听，强制刷新视图
                .id(messageCount)
            }
            
            // 底部控制区域
            VStack {
                // 格式选择器
                HStack {
                    Text("发送格式:")
                        .font(.system(size: 14))
                    
                    Picker("消息格式", selection: $viewModel.selectedFormat) {
                        ForEach(MessageFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.horizontal)
                
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
            }
            
            // 输入框
            HStack {
                // 使用本地状态变量
                TextField("输入消息", text: $localMessageText)
                    .id("messageInputField_\(topic.id)")
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .focused($isInputFocused)
                    .submitLabel(.send) // 设置键盘上的回车键为发送
                    .onSubmit {
                        sendCurrentMessage()
                    }
                    // 禁用自动更正功能
                    .disableAutocorrection(true)
                    // 使用onAppear初始化本地文本
                    .onAppear {
                        localMessageText = viewModel.messageText
                    }
                    // 当本地文本变化时同步到ViewModel
                    .onChange(of: localMessageText) { newValue in
                        // 文本过长时裁剪
                        if newValue.count > 5000 {
                            localMessageText = String(newValue.prefix(5000))
                        }
                        // 延迟同步到ViewModel，避免频繁更新
                        DispatchQueue.main.async {
                            viewModel.messageText = localMessageText
                        }
                    }
                    // 当ViewModel的文本变化时同步到本地
                    .onChange(of: viewModel.messageText) { newValue in
                        if newValue != localMessageText {
                            localMessageText = newValue
                        }
                    }
                
                Button(action: {
                    sendCurrentMessage()
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .padding(.trailing)
            }
            .padding(.vertical)
        }
        .onAppear {
            messageCount = topic.messages.count
            print("ChatView appeared，消息数量: \(messageCount)")
            
            // 如果消息很多，则显示加载更多按钮
            showLoadMoreButton = topic.messages.count > messagesPerPage
            
            // 如果消息太多，可以自动增加每页显示消息数
            if topic.messages.count > 300 {
                messagesPerPage = 50
            } else if topic.messages.count > 500 {
                messagesPerPage = 70
            }
            
            // 确保至少显示第一页
            currentPage = 1
            
            // 初始化本地文本
            localMessageText = viewModel.messageText
        }
        // 添加复制成功的提示
        .alert("已复制全部消息到剪贴板", isPresented: $showCopiedAlert) {
            Button("确定", role: .cancel) { }
        }
    }
    
    // 抽取发送消息逻辑到单独的方法
    private func sendCurrentMessage() {
        if !localMessageText.isEmpty {
            let textToSend = localMessageText
            
            // 先清空输入框
            localMessageText = ""
            viewModel.messageText = ""
            
            // 取消键盘焦点
            isInputFocused = false
            
            // 使用延迟发送，避免UI卡顿
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if viewModel.isConnected {
                    // 发送消息
                    viewModel.sendMessage(textToSend, to: topic)
                    // 设置滚动到底部
                    scrollToBottom = true
                } else {
                    // 如果未连接，显示提示
                    viewModel.showAlert("MQTT未连接，请先连接MQTT服务器")
                }
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


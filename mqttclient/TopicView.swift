import SwiftUI

struct TopicView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var selectedTab: Int
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var showingAddTopicAlert = false
    @State private var newTopicName = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // Topic列表
                List {
                    ForEach(viewModel.topics) { topic in
                        Button(action: {
                            viewModel.selectedTopic = topic
                            selectedTab = 1  // 切换到主页
                        }) {
                            HStack {
                                Text(topic.name)
                                   .font(.system(size: 18, weight: .medium))
                                   .foregroundColor(.primary)
                                    .padding(.vertical, 10)
//                                
                                    Spacer()
                            }
                        }
//                        .listRowBackground(viewModel.selectedTopic?.id == topic.id ? Color("mqttPurple").opacity(0.2) : Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.alertType = .deleteTopic(topic: topic)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        guard let index = indexSet.first else { return }
                        let topicToDelete = viewModel.topics[index]
                        viewModel.alertType = .deleteTopic(topic: topicToDelete)
                    }
                }
                .listStyle(InsetGroupedListStyle()) // 使用分组列表样式
            }
            .navigationBarTitle("Topics", displayMode: .inline,)
            .navigationBarItems(
                trailing: Button(action: {
                    showingAddTopicAlert = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color("mqttPurple"))
                }
            )
            .alert("添加新Topic", isPresented: $showingAddTopicAlert) {
                TextField("输入Topic名称", text: $newTopicName)
                Button("取消", role: .cancel) {
                    newTopicName = ""
                }
                Button("添加") {
                    if !newTopicName.isEmpty {
                        let newTopic = Topic(name: newTopicName)
                        viewModel.topics.append(newTopic)
                        newTopicName = ""
                        viewModel.saveTopics()
                        
                        // 如果已连接MQTT，立即订阅新主题
                        if viewModel.isConnected, let session = viewModel.getSession() {
                            let qosLevel = viewModel.selectedQoS.mqttQoS
                            session.subscribe(toTopic: newTopic.name, at: qosLevel, subscribeHandler: { error, gQoss in
                                if let error = error {
                                    print("订阅新Topic失败: \(newTopic.name), 错误: \(error.localizedDescription)")
                                    viewModel.showAlert("订阅失败: \(error.localizedDescription)")
                                } else {
                                    print("成功订阅新Topic: \(newTopic.name), QoS: \(gQoss?.first?.intValue ?? -1)")
                                }
                            })
                            print("已请求订阅新Topic: \(newTopic.name)，使用QoS级别: \(viewModel.selectedQoS.rawValue)")
                        }
                    }
                }
            }
            // 确保iPad上有默认内容
            Text("请选择一个Topic")
                .font(.title)
                .foregroundColor(.gray)
        }
         .navigationViewStyle(StackNavigationViewStyle())
    }
    
}

#Preview {
    TopicView(viewModel: HomeViewModel(), selectedTab: .constant(0))
}

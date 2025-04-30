import SwiftUI

struct TopicView: View {
    @ObservedObject var viewModel: HomwViewModel
    @Binding var selectedTab: Int
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
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
                                
                                Spacer()
                            }
                        }
                        .listRowBackground(viewModel.selectedTopic?.id == topic.id ? Color.blue.opacity(0.2) : Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.alertType = .deleteTopic(topic: topic)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        // 处理删除操作
                        guard let index = indexSet.first else { return }
                        let topicToDelete = viewModel.topics[index]
                        viewModel.alertType = .deleteTopic(topic: topicToDelete)
                    }
                }
                .listStyle(InsetGroupedListStyle())
                
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
                            
                            // 如果已连接MQTT，立即订阅新主题
                            if viewModel.isConnected, let session = viewModel.getSession() {
                                let qosLevel = viewModel.selectedQoS.mqttQoS
                                session.subscribeToTopic(newTopic.name, atLevel: qosLevel, subscribeHandler: { error, gQoss in
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
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing)
                }
                .padding(.vertical)
            }
            .navigationBarTitle("Topics", displayMode: .inline)
            
            // 确保iPad上有默认内容（这个视图在iPad分屏模式下会显示）
            Text("请选择一个Topic")
                .font(.title)
                .foregroundColor(.gray)
        }
        // 使用StackNavigationViewStyle确保在所有设备上使用单一视图
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    TopicView(viewModel: HomwViewModel(), selectedTab: .constant(0))
}
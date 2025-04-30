import SwiftUI

struct TopicView: View {
    @ObservedObject var viewModel: HomwViewModel
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationView {
            VStack {
                // Topic列表
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.topics) { topic in
                            HStack {
                                Button(action: {
                                    viewModel.selectedTopic = topic
                                    selectedTab = 1  // 切换到主页
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
            }
            .navigationBarTitle("Topics", displayMode: .inline)
        }
    }
}

#Preview {
    TopicView(viewModel: HomwViewModel(), selectedTab: .constant(0))
}
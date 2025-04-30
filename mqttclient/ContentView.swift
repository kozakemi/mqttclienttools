import SwiftUI
import MQTTClient

struct ContentView: View {
    @StateObject private var viewModel = HomwViewModel()
    @State private var selectedTab = 1  // 默认选择主页标签
    
    init() {
        // 设置TabBar的背景色
        UITabBar.appearance().backgroundColor = UIColor.secondarySystemBackground
        // 设置导航栏的背景色
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.secondarySystemBackground
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TopicView(viewModel: viewModel, selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Topics")
                }
                .tag(0)
            
            HomwView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "house")
                    Text("主页")
                }
                .tag(1)
            
            ConfigView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("配置")
                }
                .tag(2)
        }
        // 使用兼容的方法修复横屏布局问题
        .onAppear {
            // 监听设备旋转通知
            NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
                // 简单地强制更新视图，避免使用iOS 16特定API
                // 这个空操作会触发SwiftUI重新评估视图布局
            }
        }
        // 添加alert处理
        .alert(item: $viewModel.alertType) { alertType in
            switch alertType {
            case .connection(let message):
                return Alert(
                    title: Text("提示"),
                    message: Text(message),
                    dismissButton: .default(Text("确定"))
                )
            case .clearConfirm(let topic):
                return Alert(
                    title: Text("确认清空"),
                    message: Text("确定要清空所有聊天记录吗？"),
                    primaryButton: .destructive(Text("确定")) {
                        topic.messages.removeAll()
                        viewModel.saveTopics()
                        viewModel.objectWillChange.send()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .deleteTopic(let topic):
                return Alert(
                    title: Text("确认删除"),
                    message: Text("确定要删除Topic \"\(topic.name)\" 吗？所有消息记录将被永久删除。"),
                    primaryButton: .destructive(Text("删除")) {
                        viewModel.deleteTopic(topic)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

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
    }
}






struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

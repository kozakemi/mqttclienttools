import SwiftUI
import MQTTClient

struct ContentView: View {
    
    var body: some View {
        TabView {
            HomwView()
                .tabItem {
                    Image(systemName: "house")
                    Text("主页")
                }
                    
            ConfigView()
                .tabItem {
                    Image(systemName: "person")
                    Text("配置")
                }
        }
    }
}






struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

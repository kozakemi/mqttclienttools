import SwiftUI
import MQTTClient
struct ContentView: View {
    @State var change=false;
    var body: some View {
        VStack {
            GeometryReader { geometry in
                VStack {
                    Image("UserImg")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width / 2)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(.white, lineWidth: 4)
                        }
                        .shadow(radius: 7)


                    VStack(alignment: .leading) {
                        Text("Kozakemi")
                            .font(.title)

                        Text("嵌入式&移动应用&云计算")
                            .font(.subheadline)
                        Divider()
                        Text("gitlab:https://gitlab.com/kozakemi")
                            .font(.subheadline)
                        Text("blog:https://kozakemi.gitlab.io")
                            .font(.subheadline)
                    }
                    
                    Button(action: {
                        self.change.toggle()
                    }, label: {
                        HStack(content: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                            Text("Hello World")
                                .font(.subheadline)
                        })
                        .frame(width: geometry.size.width / 4)
                        .padding()
                        .foregroundColor(.white)
                        .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.blue]), startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(40)
                    })
                }
                .padding()
//                .frame(height: geometry.size.height) // 设置高度为GeometryReader的高度
            }
        }
        .frame(maxHeight: .infinity) // 让VStack填充剩余的空间
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

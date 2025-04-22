//
//  AboutMeView.swift
//  mqttclient
//
//  Created by kozakemi on 2024/2/26.
//

import SwiftUI

struct AboutMeView: View {
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
                }
                .padding()
//                .frame(height: geometry.size.height) // 设置高度为GeometryReader的高度
            }
        }
        .frame(maxHeight: .infinity) // 让VStack填充剩余的空间
        .navigationBarTitle("关于我")
    
    }
}


#Preview {
    AboutMeView()
}

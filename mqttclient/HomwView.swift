//
//  HomwView.swift
//  mqttclient
//
//  Created by kozakemi on 2024/2/26.
//

import SwiftUI

struct HomwView: View {
    @State private var variable = false;
    var body: some View {
        NavigationView {
            HStack{
                Text(String(variable));
            }
            .navigationBarTitle("主页", displayMode: .inline)
            .navigationBarItems(
                leading: NavigationLink(destination: AboutMeView()) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.blue)
               },
               trailing: Toggle(isOn: $variable) {
                   Text("状态")
               }
           )
        }
        let toolbar = UIToolbar()
    }
}

#Preview {
    HomwView()
}

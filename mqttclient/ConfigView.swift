//
//  ConfigView.swift
//  mqttclient
//
//  Created by kozakemi on 2024/2/26.
//

import SwiftUI
import CryptoKit

struct ConfigView: View {
    @State private var ipAddress = ""
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var clientId = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showPassword = false
    @State private var showAboutMe = false
    @State private var ignoreOwnMessages = false
    @ObservedObject var mqttViewModel: HomwViewModel // 直接使用传递的ViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // 添加环境变量来访问UIApplication
    @Environment(\.scenePhase) private var scenePhase
    
    let defaults = UserDefaults.standard
    
    // 生成随机客户端ID的方法
    private func generateRandomClientId() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let prefix = "mqttClient_"
        let randomPart = String((0..<10).map { _ in letters.randomElement()! })
        return prefix + randomPart
    }
    
    // 添加收起键盘的方法
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func encryptPassword(_ password: String) -> String {
        guard let data = password.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func validateInputs() -> Bool {
        if ipAddress.isEmpty {
            alertMessage = "请输入服务器地址"
            return false
        }
        if port.isEmpty {
            alertMessage = "请输入端口号"
            return false
        }
        if let portNumber = Int(port) {
            if portNumber <= 0 || portNumber > 65535 {
                alertMessage = "端口号必须在1-65535之间"
                return false
            }
        } else {
            alertMessage = "端口号必须是有效数字"
            return false
        }
        return true
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 服务器连接设置区域
                    VStack(alignment: .leading, spacing: 10) {
                        Text("服务器连接")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        ForEach(["MQTT服务器地址", "MQTT服务器端口", "用户名", "密码", "客户端ID"], id: \.self) { title in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(title)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                if title == "密码" {
                                    HStack {
                                        if showPassword {
                                            TextField("Password", text: $password)
                                        } else {
                                            SecureField("Password", text: $password)
                                        }
                                        
                                        Button(action: {
                                            showPassword.toggle()
                                        }) {
                                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                } else {
                                    TextField(title == "MQTT服务器地址" ? "IP Address/Header" :
                                             title == "MQTT服务器端口" ? "Port" :
                                             title == "用户名" ? "Username" : "Client ID",
                                             text: title == "MQTT服务器地址" ? $ipAddress :
                                             title == "MQTT服务器端口" ? $port :
                                             title == "用户名" ? $username : $clientId)
                                    .keyboardType(title == "MQTT服务器端口" ? .numberPad : .default)
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    
                    // 消息显示选项区域
                    VStack(alignment: .leading, spacing: 10) {
                        Text("消息显示选项")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        Toggle("忽略自己发送的消息回显", isOn: Binding(
                            get: { mqttViewModel.ignoreOwnMessages },
                            set: { newValue in
                                DispatchQueue.main.async {
                                    mqttViewModel.ignoreOwnMessages = newValue
                                    defaults.set(newValue, forKey: "ignoreOwnMessages")
                                }
                            }
                        ))
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    VStack(spacing: 20) {
                        Button(action: {
                            if validateInputs() {
                                // 保存到 UserDefaults
                                self.defaults.set(self.ipAddress, forKey: "ipAddress")
                                self.defaults.set(Int(self.port) ?? 0, forKey: "port")
                                self.defaults.set(self.username, forKey: "username")
                                self.defaults.set(self.password, forKey: "password")
                                self.defaults.set(self.clientId, forKey: "clientId")  // 保存客户端ID
                                self.defaults.set(mqttViewModel.ignoreOwnMessages, forKey: "ignoreOwnMessages")  // 保存消息显示选项
                                
                                alertMessage = "配置保存成功"
                                showAlert = true
                            } else {
                                showAlert = true
                            }
                        }) {
                            Text("保存")
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                        Button(action: {
                            showAboutMe = true
                        }) {
                            HStack {
                                Image(systemName: "person.circle")
                                Text("关于我")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding()
                .onAppear {
                    // 在视图出现时加载数据
                    self.ipAddress = defaults.string(forKey: "ipAddress") ?? ""
                    let savedPort = defaults.integer(forKey: "port")
                    self.port = savedPort > 0 ? String(savedPort) : "1883"
                    self.username = defaults.string(forKey: "username") ?? ""
                    self.password = defaults.string(forKey: "password") ?? ""
                    
                    // 加载客户端ID，如果不存在则生成一个随机ID
                    if let savedClientId = defaults.string(forKey: "clientId"), !savedClientId.isEmpty {
                        self.clientId = savedClientId
                    } else {
                        self.clientId = generateRandomClientId()
                    }
                    
                    // 在视图出现时从UserDefaults同步设置到ViewModel
                    let savedIgnoreMessages = defaults.bool(forKey: "ignoreOwnMessages")
                    // 仅当值不同时才更新，避免不必要的状态变化
                    if mqttViewModel.ignoreOwnMessages != savedIgnoreMessages {
                        // 使用异步更新避免阻塞UI
                        DispatchQueue.main.async {
                            mqttViewModel.ignoreOwnMessages = savedIgnoreMessages
                        }
                    }
                }
            }
            .navigationBarTitle("MQTT配置", displayMode: .inline)
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertMessage))
            }
            .sheet(isPresented: $showAboutMe) {
                AboutMeView()
            }
            // 添加点击手势来收起键盘
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            
            // 确保iPad上有默认内容（这个视图在iPad分屏模式下会显示）
            Text("在配置页面设置MQTT参数")
                .font(.title)
                .foregroundColor(.gray)
        }
        // 使用StackNavigationViewStyle确保在所有设备上使用单一视图
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    ConfigView(mqttViewModel: HomwViewModel())
}

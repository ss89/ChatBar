//
//  ChatConnection.swift
//  ChatBar
//
//  Created by Lukas Huwald on 07.03.17.
//  Copyright © 2017 Lukas Huwald.
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at

//  http://www.apache.org/licenses/LICENSE-2.0

//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import Cocoa
import Starscream

@available(OSX 10.14, *)
// This class handles the socket connection to twitch IRC
class ChatConnection: WebSocketDelegate {

    // IRC Commands that can be send
    enum ChatCommand {
        case JOIN
        case PART
        case NICK
        case PONG
    }
    
    // store user data and channel name for connection
    var channelName: String?

    var username: String?
    
    // the socket object
    var socket: WebSocket?
    
    // reference to window controller
    var wc: ChatBarWindowController
    
    // initializer
    init(wc: ChatBarWindowController) {
        self.wc = wc
    }
    
    // connect to Twitch IRC and join channel
    func connect(channel: String){
        if socket != nil {
            // already connected, part old channel and join new channel
            self.partChannel()
            self.joinChannel(channel: channel)
        }
        else {
            // form new connection
            self.channelName = channel
            // use justinfanXXXXXXXXXX username which allows login without oauth tokens
            let digits = "0123456789"
            self.username = "justinfan"
            for _ in 1 ... 10 {
                self.username!.append(digits.randomElement()!)
            }
            
            self.open()
        }
    }
    
    // open socket and try connecting
    func open() {
        // connect to SSL port
        let target = URL(string: "wss://irc-ws.chat.twitch.tv:443")
        socket = WebSocket(url: target!)
        socket!.enabledSSLCipherSuites = [
            TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
            TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        ]
        socket!.delegate = self
        socket!.connect()
    }
    
    // on connect: send PASS/NICK and join channel
    func websocketDidConnect(socket: WebSocketClient) {
        self.send(command: ChatCommand.NICK, msg: self.username!)
        self.joinChannel(channel: channelName!)
        wc.updateStatus(description: "OK")
    }
    
    // on disconnect: show error if any occurred
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        if error != nil {
            wc.updateStatus(description: "Connection error. Try again.")
        }
    }
    
    // on receive: respond to pings, update touchbar
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        var lines : [String] = []
        // split into messages
        text.enumerateLines { line, _ in lines.append(line) }
        if lines.count == 0 {
            // no message read
            return
        }
        // check for ping message and respond with pong
        for line in lines {
            if line == "PING :tmi.twitch.tv" {
                self.send(command: ChatCommand.PONG, msg: "")
            }
        }
        // return info about first message
        for line in lines {
            if line.contains("PRIVMSG") {
                let chatMsg = self.toMessage(line: line)
                wc.updateBar(msg: chatMsg)
            }
        }

    }
    
    // we do not expect data frames and ignore them
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {}
    
    // extract username and content of a PRIVMSG message
    func toMessage(line: String) -> ChatMessage {
        // extract username
        let line = line[line.index(line.startIndex, offsetBy: 1)...]
        let endUser = line.firstIndex(of: "!")!
        let userName = String(line.prefix(upTo: endUser))
        // extract message
        let startMsgRange = line.range(of: " :")!
        let msgRange = Range(uncheckedBounds: (lower: startMsgRange.upperBound, upper: line.endIndex))
        let message = String(line[msgRange])
        return ChatMessage(user: userName, content: message)
        
    }
    
    // join a twitch chat channel
    func joinChannel(channel: String) {
        self.channelName = channel
        self.send(command: ChatCommand.JOIN, msg: channel)
    }
    
    // part a twitch chat channel
    func partChannel() {
        if let cname = self.channelName {
            self.send(command: ChatCommand.PART, msg: cname)
            self.channelName = nil
        }
    }
    
    // close socket
    func close() {
        self.socket!.disconnect()
        self.socket = nil
    }
    
    // send IRC command over socket
    func send(command: ChatCommand, msg: String) {
        var payload : String
        switch command {
        case .NICK:
            payload = "NICK "
        case .JOIN:
            payload = "JOIN #"
        case .PART:
            payload = "PART #"
        case .PONG:
            payload = "PONG :tmi.twitch.tv"
        }
        payload += msg
        // IRC requires CR+LF
        payload += "\r\n"
        // send message over socket
        self.socket!.write(string: payload) 
        
    }
    
}

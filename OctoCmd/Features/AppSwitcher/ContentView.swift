//
//  ContentView.swift
//  OctoCmd
//
//  Created by Huy Tran on 4/25/23.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Pick an application")
                .fontWeight(.heavy)
                .font(.system(size: 21.0))
                .background(.clear)
                .padding(.leading)
            
            List(sharedData.windows) { win in
                HStack {
                    Text("\(win.alias)")
                        .bold()
                        .padding(2)
                        .font(.system(size: 13.0).monospaced())
                        .frame(width: 22.0, height: 22.0)
                        .background(.bar)
                        .cornerRadius(4.0)
                        .opacity(sharedData.ignored.contains(win.pid) ? 0.25 : 1.0)
                    Image(nsImage: win.icon)
                        .frame(width: 24.0, height: 22.0)
                        .scaledToFit()
                        .opacity(sharedData.ignored.contains(win.pid) ? 0.25 : 1.0)
                    Text("\(win.name)")
                        .padding(2)
                        .font(.system(size: 15.0))
                        .opacity(sharedData.ignored.contains(win.pid) ? 0.25 : 1.0)
                    Spacer()
                    Button(sharedData.ignored.contains(win.pid) ? "add" : "skip") {
                        sharedData.togglePidIgnore(pid: win.pid)
                    }
                    .cornerRadius(11.0)
                    .font(.system(size: 10.0).monospaced())
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 4.0)
            }
            .background(.clear)
            .scrollContentBackground(.hidden)
                        
            Spacer()
            
            HStack(spacing: 4.0) {
                Text("Press")
                Text("ESC")
                    .padding(1.0)
                    .padding(.trailing, 4.0)
                    .padding(.leading, 4.0)
                    .font(.system(size: 12.0).monospaced())
                    .background(.bar)
                    .foregroundColor(.primary)
                    .cornerRadius(4.0)
                Text("to close.")
                Text("⌘ + Q")
                    .padding(1.0)
                    .padding(.trailing, 4.0)
                    .padding(.leading, 4.0)
                    .font(.system(size: 12.0).monospaced())
                    .background(.red)
                    .foregroundColor(.white)
                    .cornerRadius(4.0)
                Text("to exit.")
            }
            .padding()
        }
        .padding(0)
        .frame(width: 330, height: 500)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var sharedData = SharedData()
    static var previews: some View {
        ContentView()
            .environmentObject(sharedData)
    }
}

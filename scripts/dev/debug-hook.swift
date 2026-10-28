import Foundation
let args = CommandLine.arguments
let name = args[1] == "snap" ? "app.freefield.debug.snapshot" : "app.freefield.debug.navigate"
DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: args[2], userInfo: nil, deliverImmediately: true)
RunLoop.main.run(until: Date().addingTimeInterval(0.2))

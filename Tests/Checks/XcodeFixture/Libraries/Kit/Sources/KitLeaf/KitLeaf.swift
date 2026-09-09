/// Two modules away from the App target: reachable only through KitCore.
public protocol Reporting {
  func report(_ event: String)
}

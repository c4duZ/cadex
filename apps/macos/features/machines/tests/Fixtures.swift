import Foundation

// Answers of the Tailscale LocalAPI, in the shape read on this Mac on
// 2026-11-16 (Tailscale 1.104.7, `GET /localapi/v0/status`), with made-up
// names and addresses. `tailscale status --json` gives the same shape.

/// This Mac, a PC straight, a Linux box through a relay, an old laptop off.
let statusRunning = """
{"Version":"1.104.7","BackendState":"Running","TailscaleIPs":["100.64.0.1"],
 "MagicDNSSuffix":"tail1234.ts.net",
 "Self":{"ID":"nSelf","HostName":"My Mac","DNSName":"my-mac.tail1234.ts.net.","OS":"macOS",
   "UserID":1,"TailscaleIPs":["100.64.0.1","fd7a:115c:a1e0::1"],"Online":true,"Relay":"sao","CurAddr":"",
   "Active":false,"LastSeen":"0001-01-01T00:00:00Z"},
 "Peer":{
   "key:a":{"ID":"nPC","HostName":"DESKTOP-1","DNSName":"pc.tail1234.ts.net.","OS":"linux","UserID":1,
     "TailscaleIPs":["100.64.0.2"],"Online":true,"Relay":"sao","CurAddr":"192.168.0.9:41641","Active":true,
     "LastSeen":"2026-11-16T10:00:00Z"},
   "key:b":{"ID":"nBox","HostName":"box","DNSName":"box.tail1234.ts.net.","OS":"linux","UserID":2,
     "TailscaleIPs":["100.64.0.3"],"Online":true,"Relay":"fra","CurAddr":"","Active":true,
     "LastSeen":"2026-11-16T10:00:00.123456Z"},
   "key:c":{"ID":"nOld","HostName":"old-laptop","DNSName":"old-laptop.tail1234.ts.net.","OS":"windows","UserID":1,
     "TailscaleIPs":["100.64.0.4"],"Online":false,"Relay":"sao","CurAddr":"","Active":false,
     "LastSeen":"2026-11-16T07:00:00Z"}},
 "User":{"1":{"ID":1,"LoginName":"owner@example.com","DisplayName":"Owner"},
         "2":{"ID":2,"LoginName":"friend@example.com","DisplayName":"Friend"}}}
"""

/// An older Tailscale: no OS, no Active, no CurAddr; a peer without MagicDNS.
let statusOld = """
{"BackendState":"Running",
 "Self":{"HostName":"My Mac","DNSName":"","TailscaleIPs":["100.64.0.1"],"Online":true},
 "Peer":{"key:a":{"HostName":"pc","DNSName":"","TailscaleIPs":["100.64.0.2"],"Online":true}}}
"""

let statusNeedsLogin = """
{"BackendState":"NeedsLogin","Self":{"HostName":"My Mac","DNSName":"","OS":"macOS","TailscaleIPs":[],"Online":false},"Peer":null}
"""

let statusAlone = """
{"BackendState":"Running","Self":{"ID":"nSelf","HostName":"My Mac","DNSName":"my-mac.tail1234.ts.net.","OS":"macOS",
 "TailscaleIPs":["100.64.0.1"],"Online":true},"Peer":null}
"""

let statusBroken = #"{"BackendState":"Running","Self":{"HostName":"#

// `POST /localapi/v0/ping?type=disco` (the shape read on 2026-11-16).
let pingDirect = #"{"IP":"100.64.0.2","NodeName":"pc","Err":"","LatencySeconds":0.0123,"Endpoint":"192.168.0.9:41641","DERPRegionID":0,"DERPRegionCode":""}"#
let pingRelay = #"{"IP":"100.64.0.3","NodeName":"box","Err":"","LatencySeconds":0.08,"Endpoint":"","DERPRegionID":15,"DERPRegionCode":"fra"}"#
let pingFailed = #"{"IP":"100.64.0.4","Err":"timeout","LatencySeconds":0,"Endpoint":"","DERPRegionCode":""}"#

// The watch stream: the engine's counters every 2 s, then a state change.
let busEngine = #"{"Version":"1.104.7","ErrMessage":null,"LoginFinished":null,"State":null,"Prefs":null,"Engine":{"RBytes":0,"WBytes":0,"NumLive":1,"LiveDERPs":1},"BrowseToURL":null,"DriveShares":null}"#
let busEngineMore = #"{"Version":"1.104.7","Engine":{"RBytes":10,"WBytes":20,"NumLive":2,"LiveDERPs":1}}"#
let busState = #"{"Version":"1.104.7","State":6,"Engine":null}"#

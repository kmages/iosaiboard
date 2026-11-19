import Foundation

// Copy to Config.swift and fill in the token from /etc/fixkey.env on the server.
enum Config {
    static let endpoint = URL(string: "https://fixkey.5-161-180-197.nip.io/fix")!
    static let token = "PASTE_TOKEN_HERE"
}

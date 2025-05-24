//
//  PusherService.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/26/20.
//

import Flutter
import PusherSwiftWithEncryption

class PusherService: MChannel {
    static let CHANNEL_NAME = "com.github.chinloyal/pusher_client"
    static let EVENT_STREAM = "com.github.chinloyal/pusher_client_stream"
    static let LOG_TAG = "PusherClientPlugin"
    static let PRIVATE_PREFIX = "private-"
    static let PRIVATE_ENCRYPTED_PREFIX = "private-encrypted-"
    static let PRESENCE_PREFIX = "presence-"

    private var pusher: Pusher!
    private var bindedEvents = [String: String]()

    struct Logger {
        static var isEnabled = true

        static func debug(_ message: String) {
            guard isEnabled else { return }
            debugPrint("D/\(LOG_TAG): \(message)")
        }

        static func error(_ message: String) {
            guard isEnabled else { return }
            debugPrint("E/\(LOG_TAG): \(message)")
        }
    }

    func register(messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(name: Self.CHANNEL_NAME, binaryMessenger: messenger)
        methodChannel.setMethodCallHandler(handleMethodCall(_:result:))

        let eventChannel = FlutterEventChannel(name: Self.EVENT_STREAM, binaryMessenger: messenger)
        eventChannel.setStreamHandler(StreamHandler.default)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init": initialize(call, result: result)
        case "connect": connect(result: result)
        case "disconnect": disconnect(result: result)
        case "getSocketId": result(pusher.connection.socketId)
        case "subscribe": subscribe(call, result: result)
        case "unsubscribe": unsubscribe(call, result: result)
        case "bind": bind(call, result: result)
        case "unbind": unbind(call, result: result)
        case "trigger": trigger(call, result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let json = call.arguments as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected a JSON string", details: nil))
            return
        }

        do {
            let args = try JSONDecoder().decode(PusherArgs.self, from: Data(json.utf8))
            Logger.isEnabled = args.initArgs.enableLogging

            guard pusher == nil else { return result(nil) }

            let options = PusherClientOptions(
                authMethod: args.pusherOptions.auth.map { AuthMethod.authRequestBuilder(authRequestBuilder: AuthRequestBuilder(pusherAuth: $0)) } ?? .noMethod,
                host: args.pusherOptions.cluster.map { .cluster($0) } ?? .host(args.pusherOptions.host),
                port: args.pusherOptions.encrypted ? args.pusherOptions.wssPort : args.pusherOptions.wsPort,
                useTLS: args.pusherOptions.encrypted,
                activityTimeout: Double(args.pusherOptions.activityTimeout) / 1000
            )

            pusher = Pusher(key: args.appKey, options: options)
            pusher.connection.reconnectAttemptsMax = args.pusherOptions.maxReconnectionAttempts
            pusher.connection.maxReconnectGapInSeconds = Double(args.pusherOptions.maxReconnectGapInSeconds)
            pusher.connection.pongResponseTimeoutInterval = Double(args.pusherOptions.pongTimeout) / 1000
            pusher.connection.delegate = ConnectionListener.default

            Logger.debug("Pusher initialized")
            result(nil)
        } catch {
            Logger.error(error.localizedDescription)
            result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: error))
        }
    }

    private func connect(result: @escaping FlutterResult) {
        pusher.connect()
        result(nil)
    }

    private func disconnect(result: @escaping FlutterResult) {
        pusher.disconnect()
        Logger.debug("Disconnected")
        result(nil)
    }

    private func subscribe(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: String], let channelName = args["channelName"] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing channel name", details: nil))
            return
        }

        let channel: PusherChannel = channelName.hasPrefix(Self.PRESENCE_PREFIX)
            ? pusher.subscribeToPresenceChannel(channelName: channelName)
            : pusher.subscribe(channelName)

        Constants.Events.allCases.forEach { channel.bind(eventName: $0.rawValue, eventCallback: ChannelEventListener.default.onEvent) }

        if channelName.hasPrefix(Self.PRESENCE_PREFIX) {
            Constants.PresenceEvents.allCases.forEach { channel.bind(eventName: $0.rawValue, eventCallback: ChannelEventListener.default.onEvent) }
        }

        Logger.debug("Subscribed to \(channelName)")
        result(nil)
    }

    private func unsubscribe(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: String], let channelName = args["channelName"] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing channel name", details: nil))
            return
        }

        pusher.unsubscribe(channelName)
        Logger.debug("Unsubscribed from \(channelName)")
        result(nil)
    }

    private func bind(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: String], let channelName = args["channelName"], let eventName = args["eventName"] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing binding arguments", details: nil))
            return
        }

        let channel: PusherChannel = channelName.hasPrefix(Self.PRESENCE_PREFIX)
            ? pusher.connection.channels.findPresence(name: channelName)!
            : pusher.connection.channels.find(name: channelName)!

        let callbackId = channel.bind(eventName: eventName, eventCallback: ChannelEventListener.default.onEvent)
        bindedEvents[channelName + eventName] = callbackId

        Logger.debug("[BIND] \(eventName)")
        result(nil)
    }

    private func unbind(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: String],
              let channelName = args["channelName"],
              let eventName = args["eventName"],
              let callbackId = bindedEvents[channelName + eventName] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing unbind arguments", details: nil))
            return
        }

        let channel: PusherChannel = channelName.hasPrefix(Self.PRESENCE_PREFIX)
            ? pusher.connection.channels.findPresence(name: channelName)!
            : pusher.connection.channels.find(name: channelName)!

        channel.unbind(eventName: eventName, callbackId: callbackId)
        Logger.debug("[UNBIND] \(eventName)")
        result(nil)
    }

    private func trigger(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let json = call.arguments as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected a JSON string", details: nil))
            return
        }

        do {
            let clientEvent = try JSONDecoder().decode(ClientEvent.self, from: Data(json.utf8))
            let channelName = clientEvent.channelName
            let eventName = clientEvent.eventName
            let data = clientEvent.data ?? ""

            guard channelName.hasPrefix(Self.PRIVATE_PREFIX) || channelName.hasPrefix(Self.PRESENCE_PREFIX) else {
                result(FlutterError(code: "TRIGGER_ERROR", message: "Trigger can only be used on private or presence channels.", details: nil))
                return
            }

            if channelName.hasPrefix(Self.PRIVATE_ENCRYPTED_PREFIX) {
                result(FlutterError(code: "TRIGGER_ERROR", message: "Cannot trigger on encrypted channels.", details: nil))
                return
            }

            let channel = channelName.hasPrefix(Self.PRIVATE_PREFIX)
                ? pusher.connection.channels.find(name: channelName)!
                : pusher.connection.channels.findPresence(name: channelName)!

            channel.trigger(eventName: eventName, data: data)
            Logger.debug("[TRIGGER] \(eventName)")
            result(nil)
        } catch {
            Logger.error(error.localizedDescription)
            result(FlutterError(code: "TRIGGER_ERROR", message: error.localizedDescription, details: error))
        }
    }
}
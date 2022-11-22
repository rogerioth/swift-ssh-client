
import Foundation
import NIO
import NIOSSH

class StartShellHandler: ChannelInboundHandler {
    enum StartShellError: Error {
        case endedChannel
    }

    typealias InboundIn = SSHChannelData

    let startPromise: EventLoopPromise<Void>

    init(eventLoop: EventLoop) {
        let promise = eventLoop.makePromise(of: Void.self)
        startPromise = promise
    }

    deinit {
        startPromise.fail(StartShellError.endedChannel)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        guard context.channel.isActive else { return }
        context
            .channel
            .setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .flatMap {
                let promise = context.channel.eventLoop.makePromise(of: Void.self)
                let request = SSHChannelRequestEvent.ShellRequest(wantReply: true)
                context.triggerUserOutboundEvent(
                    request,
                    promise: promise
                )
                return promise.futureResult
            }
            .whenFailure {
                self.startPromise.fail($0)
            }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            startPromise.succeed(())
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }
}

class ReadShellHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    let onData: (Data) -> Void

    init(onData: @escaping (Data) -> Void) {
        self.onData = onData
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = sshData.data, let bytes = buffer.readData(length: buffer.readableBytes) else {
            return
        }
        switch sshData.type {
        case .channel:
            onData(bytes)
        case .stdErr:
            onData(bytes)
        default:
            break
        }
        context.fireChannelRead(data)
    }
}

class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    let onClose: (SSHConnection.ConnectionError) -> Void
    private var error: Error?

    init(onClose: @escaping (SSHConnection.ConnectionError) -> Void) {
        self.onClose = onClose
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.error = error
        _ = context.close()
    }

    func channelInactive(context _: ChannelHandlerContext) {
        onClose(.requireActiveConnection)
    }
}
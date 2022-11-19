
import NIO
import NIOCore

protocol SFTPChannel {

    func close() -> Future<Void>

    func openFile(_ file: SFTPMessage.OpenFile.Payload) -> Future<SFTPMessage.Handle>
    func closeFile(_ file: SFTPFileHandle) -> Future<SFTPMessage.Status>
    func readFile(_ file: SFTPMessage.ReadFile.Payload) -> Future<SFTPMessage.ReadFile.Response>
    func writeFile(_ file: SFTPMessage.WriteFile.Payload) -> Future<SFTPMessage.Status>
    func mkdir(_ dir: SFTPMessage.MkDir.Payload) -> Future<SFTPMessage.Status>
    func readDir(_ handle: SFTPFileHandle) -> Future<SFTPMessage.ReadDir.Response>
    func openDir(path: String) -> Future<SFTPMessage.Handle>
    func realpath(path: String) -> Future<SFTPMessage.Name>
    func stat(path: String) -> Future<SFTPMessage.Attributes>
}

class IOSFTPChannel: SFTPChannel {

    private var stateMachine: SFTPClientStateMachine
    private let eventLoop: EventLoop
    private var idAllocator: SFTPRequestIDAllocator

    // MARK: - Life Cycle

    private init(idAllocator: SFTPRequestIDAllocator,
                 eventLoop: EventLoop,
                 stateMachine: SFTPClientStateMachine) {
        self.stateMachine = stateMachine
        self.eventLoop = eventLoop
        self.idAllocator = idAllocator
    }

    // MARK: - SFTP

    func close() -> Future<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        trigger(.requestDisconnection(promise))
        return promise.futureResult
    }

    func openFile(_ file: SFTPMessage.OpenFile.Payload) -> Future<SFTPMessage.Handle> {
        allocateRequestID().flatMap { id in
            self.send(.openFile(.init(requestId: id, payload: file)))
        }
        .flatMapThrowing { response in
            switch response {
            case .handle(let handle):
                return handle
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func closeFile(_ file: SFTPFileHandle) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
            self.send(.closeFile(.init(requestId: id, handle: file)))
        }
        .flatMapThrowing { response in
            switch response {
            case .status(let status):
                return status
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func readFile(_ file: SFTPMessage.ReadFile.Payload) -> Future<SFTPMessage.ReadFile.Response> {
        allocateRequestID().flatMap { id in
            self.send(.read(.init(requestId: id, payload: file)))
        }
        .flatMapThrowing { response in
            switch response {
            case .data(let data):
                return .fileData(data)
            case .status(let status):
                switch status.payload.errorCode {
                case .eof, .ok:
                    return .status(status)
                default:
                    throw SFTPError.invalidResponse
                }
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func writeFile(_ file: SFTPMessage.WriteFile.Payload) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
                self.send(.write(.init(requestId: id, payload: file)))
            }
            .flatMapThrowing { response in
                switch response {
                case .status(let status):
                    switch status.payload.errorCode {
                    case .eof, .ok:
                        return status
                    default:
                        throw SFTPError.invalidResponse
                    }
                default:
                    throw SFTPError.invalidResponse
                }
            }
    }

    func mkdir(_ dir: SFTPMessage.MkDir.Payload) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
                self.send(.mkdir(.init(requestId: id, payload: dir)))
            }
            .flatMapThrowing { response in
                switch response {
                case .status(let status):
                    switch status.payload.errorCode {
                    case .eof, .ok:
                        return status
                    default:
                        throw SFTPError.invalidResponse
                    }
                default:
                    throw SFTPError.invalidResponse
                }
            }
    }

    func readDir(_ handle: SFTPFileHandle) -> Future<SFTPMessage.ReadDir.Response> {
        allocateRequestID().flatMap { id in
                self.send(.readdir(.init(requestId: id, handle: handle)))
            }
            .flatMapThrowing { response in
                switch response {
                case .status(let status):
                    switch status.payload.errorCode {
                    case .eof, .ok:
                        return .status(status)
                    default:
                        throw SFTPError.invalidResponse
                    }
                case .name(let name):
                    return .name(name)
                default:
                    throw SFTPError.invalidResponse
                }
            }
    }

    func openDir(path: String) -> Future<SFTPMessage.Handle> {
        allocateRequestID().flatMap { id in
                self.send(.opendir(.init(requestId: id, path: path)))
            }
            .flatMapThrowing { response in
                switch response {
                case .handle(let handle):
                    return handle
                default:
                    throw SFTPError.invalidResponse
                }
            }
    }

    func realpath(path: String) -> Future<SFTPMessage.Name> {
        allocateRequestID().flatMap { id in
                self.send(.realpath(.init(requestId: id, path: path)))
            }
            .flatMapThrowing { response in
                switch response {
                case .name(let name):
                    return name
                default:
                    throw SFTPError.invalidResponse
                }
            }
    }

    func stat(path: String) -> Future<SFTPMessage.Attributes> {
        allocateRequestID().flatMap { id in
                self.send(.stat(.init(requestId: id, path: path)))
            }
            .flatMapThrowing { response in
                switch response {
                case .attributes(let attributes):
                    return attributes
                default:
                    throw SFTPError.invalidResponse
                }
            }
    }

    // MARK: - Private

    private func allocateRequestID() -> Future<SFTPRequestID> {
        eventLoop.submit {
            self.idAllocator.allocateRequestID()
        }
    }

    private func send(_ message: SFTPMessage) -> Future<SFTPResponse> {
        let promise = eventLoop.makePromise(of: SFTPResponse.self)
        trigger(.requestMessage(message, promise))
        return promise.futureResult
    }

    private func trigger(_ event: SFTPClientEvent) {
        eventLoop.execute {
            let action = self.stateMachine.handle(event)
            self.handle(action)
        }
    }

    private func handle(_ action: SFTPClientAction) {
        switch action {
        case let .emitMessage(message, channel):
            channel
                .writeAndFlush(message)
                .whenComplete { [weak self] result in
                    switch result {
                    case .success:
                        self?.trigger(.messageSent(message))
                    case let .failure(error):
                        self?.trigger(.messageFailed(message, error))
                    }
                }
        case let .disconnect(channel):
            // SFTPChannel already listens `close` event in `launch`
            _ = channel
                .close()
        case .none:
            break
        }
    }
}

extension IOSFTPChannel {

    static func launch(on channel: Channel) -> EventLoopFuture<IOSFTPChannel> {
        let deserializeHandler = ByteToMessageHandler(SFTPMessageParser())
        let serializeHandler = MessageToByteHandler(SFTPMessageSerializer())
        let sftpChannel = IOSFTPChannel(
            idAllocator: MonotonicRequestIDAllocator(start: 0),
            eventLoop: channel.eventLoop,
            stateMachine: SFTPClientStateMachine(channel: channel)
        )
        let sftpInboundHandler = SFTPClientInboundHandler { [weak sftpChannel] response in
            sftpChannel?.trigger(.inboundMessage(response))
        }
        let startPromise = channel.eventLoop.makePromise(
            of: Void.self
        )
        channel.closeFuture.whenComplete { [weak sftpChannel] _ in
            sftpChannel?.trigger(.disconnected)
        }
        return channel.pipeline.addHandlers(
            deserializeHandler,
            serializeHandler,
            sftpInboundHandler,
            NIOCloseOnErrorHandler()
        )
        .flatMap {
            sftpChannel.trigger(.start(startPromise))
            return startPromise.futureResult.map { sftpChannel }
        }
    }
}
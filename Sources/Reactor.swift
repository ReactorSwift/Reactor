import Foundation


// MARK: - State

public protocol State {
    mutating func react(to event: Event)
}


// MARK: - Events

public protocol Event {}


// MARK: - Commands

public protocol AnyCommand {
    func _execute(state: Any, core: Any)
    func _canExecute(state: Any) -> Bool
    var expiresAfter: TimeInterval { get }
}

extension AnyCommand {
    var expiresAfter: TimeInterval { return 10.0 }
}

public protocol Command: AnyCommand {
    associatedtype StateType: State
    func execute(state: StateType, core: Core<StateType>)
    func canExecute(state: StateType) -> Bool
}

extension Command {

    public func canExecute(state: StateType) -> Bool {
        return true
    }

    public func _canExecute(state: Any) -> Bool {
        if let state = state as? StateType {
            return canExecute(state: state)
        } else {
            return false
        }
    }

    public func _execute(state: Any, core: Any) {
        if let state = state as? StateType, let core = core as? Core<StateType> {
            execute(state: state, core: core)
        }
    }
}

public struct Commands<StateType: State> {
    private(set) var expiresAt: Date
    private(set) var command: AnyCommand
}


// MARK: - Middlewares

public protocol AnyMiddleware {
    func _process(event: Event, state: Any)
}

public protocol Middleware: AnyMiddleware {
    associatedtype StateType
    func process(event: Event, state: StateType)
}

extension Middleware {
    public func _process(event: Event, state: Any) {
        if let state = state as? StateType {
            process(event: event, state: state)
        }
    }
}

public struct Middlewares<StateType: State> {
    private(set) var middleware: AnyMiddleware
}


// MARK: - Subscribers

public protocol AnySubscriber: class {
    func _update(with state: Any)
}

public protocol Subscriber: AnySubscriber {
    associatedtype StateType
    func update(with state: StateType)
}

extension Subscriber {
    public func _update(with state: Any) {
        if let state = state as? StateType {
            update(with: state)
        }
    }
}

public struct Subscription<StateType: State> {
    private(set) weak var subscriber: AnySubscriber? = nil
    let selector: ((StateType) -> Any)?
    let notifyQueue: DispatchQueue

    fileprivate func notify(with state: StateType) {
        notifyQueue.async {
            if let selector = self.selector {
                self.subscriber?._update(with: selector(state))
            } else {
                self.subscriber?._update(with: state)
            }
        }
    }
}



// MARK: - Core

public class Core<StateType: State> {
    
    private let jobQueue:DispatchQueue = DispatchQueue(label: "reactor.core.queue", qos: .userInitiated, attributes: [])

    private let internalSyncQueue = DispatchQueue(label: "reactor.core.internal.sync")
    private var _subscriptions = [Subscription<StateType>]()
    private var subscriptions: [Subscription<StateType>] {
        get {
            return internalSyncQueue.sync {
                return self._subscriptions
            }
        }
        set {
            internalSyncQueue.sync {
                self._subscriptions = newValue
            }
        }
    }
    private var _commands = [Commands<StateType>]()
    private var commands: [Commands<StateType>] {
        get {
            return internalSyncQueue.sync {
                return self._commands
            }
        }
        set {
            internalSyncQueue.sync {
                self._commands = newValue
            }
        }
    }

    private let middlewares: [Middlewares<StateType>]
    public private (set) var state: StateType {
        didSet {
            subscriptions = subscriptions.filter { $0.subscriber != nil }
            for subscription in subscriptions {
                subscription.notify(with: state)
            }
        }
    }
    
    public init(state: StateType, middlewares: [AnyMiddleware] = []) {
        self.state = state
        self.middlewares = middlewares.map(Middlewares.init)
    }
    
    
    // MARK: - Subscriptions
    
    public func add(subscriber: AnySubscriber, notifyOnQueue queue: DispatchQueue? = DispatchQueue.main, selector: ((StateType) -> Any)? = nil) {
        jobQueue.async {
            guard !self.subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
            let subscription = Subscription(subscriber: subscriber, selector: selector, notifyQueue: queue ?? self.jobQueue)
            self.subscriptions.append(subscription)
            subscription.notify(with: self.state)
        }
    }
    
    public func remove(subscriber: AnySubscriber) {
        subscriptions = subscriptions.filter { $0.subscriber !== subscriber }
    }
    
    // MARK: - Events
    
    public func fire(event: Event) {
        jobQueue.async {
            self.state.react(to: event)
            let state = self.state
            let executable = self.commands.enumerated().filter { $1.command._canExecute(state: state) }
            executable.forEach {
                self.commands.remove(at: $0)
                $1.command._execute(state: state, core: self)
            }
            let now = Date()
            let expired = self.commands.enumerated().filter { $1.expiresAt < now }
            expired.forEach { self.commands.remove(at: $0.offset) }
            self.middlewares.forEach { $0.middleware._process(event: event, state: state) }
        }
    }
    
    public func fire<C: Command>(command: C) where C.StateType == StateType {
        if command.canExecute(state: state) {
            jobQueue.async {
                command.execute(state: self.state, core: self)
            }
        } else {
            commands.append(Commands(expiresAt: Date().addingTimeInterval(command.expiresAfter), command: command))
        }
    }
    
}

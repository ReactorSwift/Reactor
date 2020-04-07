import Foundation


// MARK: - State

public protocol State {
    mutating func react(to event: Event)
}


// MARK: - Events

public protocol Event {}


// MARK: - Commands

public protocol Command {
    associatedtype StateType: State
    func execute(state: StateType, core: Core<StateType>)
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
    let id: UInt64
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

extension String {
    static func random(length: Int = 20) -> String {
        let base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in base.randomElement()! })
    }
}

class Counter {
    private var queue = DispatchQueue(label: String.random())
    private (set) var value: UInt64 = 0

    func increment() -> UInt64 {
        queue.sync {
            value += 1
            return value
        }
    }
}

// MARK: - Core

public class Core<StateType: State> {
    
    private let jobQueue: DispatchQueue
    private var subscriptions = [Subscription<StateType>]()
    private var middlewareCounter = Counter()
    private var middlewares: [Middlewares<StateType>]

    public private (set) var state: StateType {
        didSet {
            for subscription in self.subscriptions {
                subscription.notify(with: state)
            }
        }
    }
    
    public init(state: StateType, middlewares: [AnyMiddleware] = []) {
        self.state = state
        var tempMiddlewares = [Middlewares<StateType>]()
        for m in middlewares {
          tempMiddlewares.append(Middlewares(id: middlewareCounter.increment(), middleware: m))
        }
        self.middlewares = tempMiddlewares
        let qos: DispatchQoS
        if #available(macOS 10.10, *) {
            qos = .userInitiated
        } else {
            qos = .unspecified
        }
        self.jobQueue = DispatchQueue(label: "reactor.core.queue", qos: qos, attributes: [])
    }

    
    // MARK: - Subscriptions
    
    public func add(subscriber: AnySubscriber, notifyOnQueue queue: DispatchQueue? = DispatchQueue.main, selector: ((StateType) -> Any)? = nil) {
        jobQueue.async {
            guard !self.subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
            self.subscriptions = self.subscriptions.filter { $0.subscriber != nil }
            let subscription = Subscription(subscriber: subscriber, selector: selector, notifyQueue: queue ?? self.jobQueue)
            self.subscriptions.append(subscription)
            subscription.notify(with: self.state)
        }
    }
    
    public func remove(subscriber: AnySubscriber) {
        // sync to limit `nil` subscribers by ensuring they're removed before they `deinit`.
        jobQueue.sync {
            subscriptions = subscriptions.filter { $0.subscriber !== subscriber && $0.subscriber != nil }
        }
    }
    
    // MARK: - Events
    
    public func fire(event: Event) {
        jobQueue.async {
            self.state.react(to: event)
            self.middlewares.forEach { $0.middleware._process(event: event, state: self.state) }
        }
    }
    
    public func fire<C: Command>(command: C) where C.StateType == StateType {
        jobQueue.async {
            command.execute(state: self.state, core: self)
        }
    }

    public func observe(with middleware: AnyMiddleware) -> () -> () {
      let wrapper = Middlewares<StateType>(id: middlewareCounter.increment(), middleware: middleware)
      jobQueue.async {
          self.middlewares.append(wrapper)
      }
      return {
          self.jobQueue.sync {
              if let index = self.middlewares.firstIndex(where: { $0.id == wrapper.id }) {
                self.middlewares.remove(at: index)
              }
          }
      }
    }
    
}

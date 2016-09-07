import Foundation



// MARK: - State

public protocol State {
    mutating func react(to event: Event)
}


// MARK: - Events

public protocol Event {}


// MARK: - Commands


public protocol Command {
    associatedtype S: State
    func execute(state: S, reactor: Reactor<S>)
}


// MARK: - Middlewares

public protocol AnyMiddleware {
    func _process(event: Event, state: Any)
}

public protocol Middleware: AnyMiddleware {
    associatedtype State
    func process(event: Event, state: State)
}

extension Middleware {
    public func _process(event: Event, state: Any) {
        if let state = state as? State {
            process(event: event, state: state)
        }
    }
}

public struct Middlewares<ReactorState: State> {
    private(set) var middleware: AnyMiddleware
}


// MARK: - Subscribers

public protocol AnySubscriber: class {
    func _update(with state: Any)
}

public protocol Subscriber: AnySubscriber {
    associatedtype State
    func update(with state: State)
}

extension Subscriber {
    public func _update(with state: Any) {
        if let state = state as? State {
            update(with: state)
        }
    }
}

public struct Subscription<ReactorState: State> {
    private(set) weak var subscriber: AnySubscriber? = nil
    let selector: ((ReactorState) -> Any)?
}



// MARK: - Reactor

public class Reactor<ReactorState: State> {
    
    private var subscriptions = [Subscription<ReactorState>]()
    private var middlewares = [Middlewares<ReactorState>]()
    private (set) var state: ReactorState {
        didSet {
            subscriptions = subscriptions.filter { $0.subscriber != nil }
            DispatchQueue.main.async {
                for subscription in self.subscriptions {
                    self.publishStateChange(subscriber: subscription.subscriber, selector: subscription.selector)
                }
            }
        }
    }
  
  
    public init(state: ReactorState, middlewares: [AnyMiddleware] = []) {
        self.state = state
        self.middlewares = middlewares.map(Middlewares.init)
    }
    
    
    // MARK: - Subscriptions
    
    public func add(subscriber: AnySubscriber, selector: ((ReactorState) -> Any)? = nil) {
        guard !subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
        subscriptions.append(Subscription(subscriber: subscriber, selector: selector))
        publishStateChange(subscriber: subscriber, selector: selector)
    }
    
    public func remove(subscriber: AnySubscriber) {
        subscriptions = subscriptions.filter { $0.subscriber !== subscriber }
    }
    
    private func publishStateChange(subscriber: AnySubscriber?, selector: ((ReactorState) -> Any)?) {
        if let selector = selector {
            subscriber?._update(with: selector(self.state))
        } else {
            subscriber?._update(with: self.state)
        }
    }
    
    // MARK: - Events
    
    public func fire(event: Event) {
        state.react(to: event)
        middlewares.forEach { $0.middleware._process(event: event, state: state) }
    }
    
    public func fire<C: Command>(command: C) where C.S == ReactorState {
        command.execute(state: state, reactor: self)
    }
    
}

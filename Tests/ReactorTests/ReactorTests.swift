import XCTest
@testable import Reactor

// describe Reactor

// when it has many clients
class WhenReactorHasManyClients: XCTestCase {

    // it guarantees subscribers receive their own events
    func testReactorGuaranteesSubscribersReceiveTheirOwnEvents() {
        let core = Core(state: TestState())

        var subscribers = [TestSubscriber]()
        for index in 0..<1000 {
            subscribers.append(TestSubscriber(id: index))
        }
        let predicate = NSPredicate { _, _ -> Bool in
            return subscribers.reduce(true, { $0 && $1.received })
        }
        let expected = expectation(for: predicate, evaluatedWith: NSObject())

        let globalQueue: DispatchQueue
        if #available(macOS 10.10, *) {
            globalQueue = DispatchQueue.global()
        } else {
            globalQueue = DispatchQueue.global(priority: .default)
        }
        globalQueue.async {
            DispatchQueue.concurrentPerform(iterations: subscribers.count) { index in
                let subscriber = subscribers[index]
                let event = TestEvent(id: subscriber.id)
                core.add(subscriber: subscriber)
                core.fire(event: event)
                core.remove(subscriber: subscriber)
            }
        }

        wait(for: [expected], timeout: 5.0)
        XCTAssertEqual(subscribers.count, subscribers.reduce(0, { $0 + ($1.received ? 1 : 0)}))
    }

    // it guarantees subscribers receive their own commands
    func testReactorGuaranteesSubscribersReceiveTheirOwnCommands() {
        let core = Core(state: TestState())

        var subscribers = [TestSubscriber]()
        for index in 0..<1000 {
            subscribers.append(TestSubscriber(id: index))
        }
        let predicate = NSPredicate { _, _ -> Bool in
            return subscribers.reduce(true, { $0 && $1.received })
        }
        let expected = expectation(for: predicate, evaluatedWith: NSObject())

        let globalQueue: DispatchQueue
        if #available(macOS 10.10, *) {
            globalQueue = DispatchQueue.global()
        } else {
            globalQueue = DispatchQueue.global(priority: .default)
        }
        globalQueue.async {
            DispatchQueue.concurrentPerform(iterations: subscribers.count) { index in
                let subscriber = subscribers[index]
                let command = TestCommand(id: subscriber.id)
                core.add(subscriber: subscriber)
                core.fire(command: command)
                // don't remove them so that the async commands can run
            }
        }

        wait(for: [expected], timeout: 5.0)
        XCTAssertEqual(subscribers.count, subscribers.reduce(0, { $0 + ($1.received ? 1 : 0)}))
        print(subscribers.filter { !$0.received }.map { String(describing: $0) }.joined(separator: ", "))
    }

}


struct TestState: State {

    var latest = -1

    mutating func react(to event: Event) {
        switch event {
        case let e as TestEvent:
            self.latest = e.id
        default:
            break
        }
    }

}

struct TestEvent: Event {
    let id: Int
}

struct TestCommand: Command {

    let id: Int

    func execute(state: TestState, core: Core<TestState>) {
        core.fire(event: TestEvent(id: id))
    }

}

class TestSubscriber: Subscriber {

    let id: Int
    var received = false

    init(id: Int) {
        self.id = id
    }

    func update(with state: TestState) {
        if state.latest == id {
            received = true
        }
    }

}

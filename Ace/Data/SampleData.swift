import Foundation
import SwiftData

/// Example customers, jobs and dumpster rentals for showing the app before
/// real data exists. Loaded and removed from Settings › Debug.
enum SampleData {
    static func load(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            var date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            if let hour { date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date }
            return date
        }

        let customers: [Customer] = [
            Customer(name: "Linda Johnson", phone: "508-555-0147", address: "42 Elm St, Taunton, MA", notes: "Side gate code 4412"),
            Customer(name: "Mark Pereira", phone: "508-555-0182", address: "7 Bay Rd, Raynham, MA"),
            Customer(name: "Tom & Sue Keane", phone: "774-555-0103", address: "119 Winthrop St, Taunton, MA", notes: "Garage cleanout, lots of paint cans"),
            Customer(name: "Harborview Realty", phone: "508-555-0199", address: "300 Broadway, Taunton, MA", notes: "Bill the office, ask for Dana"),
            Customer(name: "Angela Ruiz", phone: "508-555-0126", address: "15 Pine Hill Ln, Berkley, MA"),
            Customer(name: "Dave Macomber", phone: "774-555-0171", address: "88 Plymouth St, Middleborough, MA"),
        ]
        customers.forEach { context.insert($0) }

        let jobs: [Job] = [
            Job(customer: customers[0], jobType: .junkRemoval, scheduledAt: day(0, hour: 9), hasTime: true, price: 300, paymentType: .cash, isPaid: false, notes: "Basement, old couch and boxes"),
            Job(customer: customers[1], jobType: .dumpsterDropOff, scheduledAt: day(0, hour: 13), hasTime: true, price: 450, paymentType: .card, isPaid: true),
            Job(customer: customers[2], jobType: .junkRemoval, scheduledAt: day(1, hour: 8), hasTime: true, price: 525, paymentType: .check, isPaid: false),
            Job(customer: customers[3], jobType: .dumpsterPickup, scheduledAt: day(1), hasTime: false, price: nil, paymentType: .unknown, isPaid: false, notes: "Call office before pickup"),
            Job(customer: customers[4], jobType: .junkRemoval, scheduledAt: day(2, hour: 10), hasTime: true, price: 200, paymentType: .cash, isPaid: false),
            Job(customer: customers[5], jobType: .dumpsterDropOff, scheduledAt: day(3, hour: 7), hasTime: true, price: 475, paymentType: .card, isPaid: false),
            Job(customer: customers[0], jobType: .junkRemoval, scheduledAt: day(-3, hour: 14), hasTime: true, price: 180, paymentType: .cash, isPaid: true),
        ]
        jobs[6].isDone = true
        jobs.forEach { context.insert($0) }

        for number in 1...6 {
            let dumpster = Dumpster(number: number, label: number <= 3 ? "15 yard" : "20 yard")
            switch number {
            case 1:
                dumpster.isOut = true
                dumpster.customer = customers[3]
                dumpster.location = customers[3].address
                dumpster.droppedOffAt = day(-9)
                dumpster.dueBackAt = day(-2)
                dumpster.price = 450
                dumpster.agreedWeightTons = 2
            case 2:
                dumpster.isOut = true
                dumpster.customer = customers[2]
                dumpster.location = customers[2].address
                dumpster.droppedOffAt = day(-7)
                dumpster.dueBackAt = day(0)
                dumpster.price = 450
                dumpster.agreedWeightTons = 2
            case 4:
                dumpster.isOut = true
                dumpster.customer = customers[4]
                dumpster.location = customers[4].address
                dumpster.droppedOffAt = day(-2)
                dumpster.dueBackAt = day(5)
                dumpster.price = 525
                dumpster.agreedWeightTons = 3
            default:
                break
            }
            context.insert(dumpster)
        }

        try? context.save()
    }

    /// Removes everything. Used before loading samples and by "Clear all data".
    static func clear(context: ModelContext) {
        try? context.delete(model: RentalRecord.self)
        try? context.delete(model: Job.self)
        try? context.delete(model: Dumpster.self)
        try? context.delete(model: Customer.self)
        try? context.save()
    }
}

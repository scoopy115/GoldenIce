//
//  PositionWeights27Tests.swift
//  Ice
//

import Testing
@testable import IceMacOS27Core

@Suite("PositionWeights27")
struct PositionWeights27Tests {
    @Test("A weight between two neighbours lands between them")
    func between() {
        let weight = PositionWeights27.weight(left: 300, right: 100, higherIsLeft: true, taken: [])
        #expect(weight == 200)
    }

    @Test("A taken weight is stepped around")
    func steppedAround() {
        let weight = PositionWeights27.weight(left: 300, right: 100, higherIsLeft: true, taken: [200])
        #expect(weight == 201)
    }

    @Test("Neighbours with no room between them ask for a respace")
    func noRoom() {
        #expect(PositionWeights27.weight(left: 101, right: 100, higherIsLeft: true, taken: []) == nil)
    }

    @Test("Neighbours in the wrong order are refused")
    func wrongOrder() {
        #expect(PositionWeights27.weight(left: 100, right: 300, higherIsLeft: true, taken: []) == nil)
    }

    @Test("A neighbour on one side only is followed at the usual spacing")
    func oneSide() {
        #expect(PositionWeights27.weight(left: 500, right: nil, higherIsLeft: true, taken: []) == 400)
        #expect(PositionWeights27.weight(left: nil, right: 500, higherIsLeft: true, taken: []) == 600)
        #expect(PositionWeights27.weight(left: 500, right: nil, higherIsLeft: false, taken: []) == 600)
    }

    @Test("An item already between its neighbours needs no write")
    func inPlace() {
        #expect(PositionWeights27.isInPlace(200, left: 300, right: 100, higherIsLeft: true))
        #expect(!PositionWeights27.isInPlace(400, left: 300, right: 100, higherIsLeft: true))
    }

    @Test("The direction is read from items whose positions are known")
    func direction() {
        let descending = [(weight: 900, x: 100.0), (weight: 500, x: 200.0), (weight: 0, x: 300.0)]
        #expect(PositionWeights27.higherIsLeft(samples: descending) == true)
        let ascending = [(weight: -900, x: 100.0), (weight: 0, x: 200.0)]
        #expect(PositionWeights27.higherIsLeft(samples: ascending) == false)
        #expect(PositionWeights27.higherIsLeft(samples: []) == nil)
    }
}

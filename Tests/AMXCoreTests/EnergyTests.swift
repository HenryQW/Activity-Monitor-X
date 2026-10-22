import CoreGraphics
import Foundation
import Testing
@testable import AMXCore

@Suite struct EnergyTests {
    private static func process(_ app: String, energy: Double) -> LiveProcess {
        LiveProcess(pid: 1, startTime: 0, name: app, appKey: app, appName: app, path: nil, cpu: 0, mem: 0, diskR: 0,
                    diskW: 0, netIn: 0, netOut: 0, gpu: 0, energy: energy)
    }

    @Test func adapterAndDischargingBattery() {
        // Registry milliamps arrive as unsigned 64-bit: this is -1371 mA.
        let registry: [String: Any] = ["Voltage": 13020, "InstantAmperage": NSNumber(value: UInt64(18446744073709550245)),
                                       "PowerTelemetryData": ["SystemPowerIn": 49099], "AdapterDetails": ["Watts": 53]]
        let source: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 79, "Max Capacity": 100, "Is Charging": false]
        let power = PowerReading(providing: "AC Power", source: source, battery: registry)
        #expect(power.adapterWatts == 49.099 && power.adapterRating == 53)
        #expect(power.battery?.percent == 79)
        #expect(abs(power.battery!.watts! + 17.85) < 0.01)
        #expect(abs(power.systemWatts! - 66.95) < 0.01)
    }

    @Test func missingKeysAreNil() {
        let power = PowerReading(providing: "AC Power", source: nil, battery: nil)
        #expect(power.adapterConnected && power.adapterWatts == nil && power.battery == nil && power.systemWatts == nil)
        let flows = EnergyFlows(power, shares: [])
        #expect(flows.columns == [[.adapter], [.mac], []])
        #expect(flows.links == [.init(from: .adapter, to: .mac, weight: 1, watts: nil)])
    }

    @Test func onBattery() {
        let source: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 64, "Max Capacity": 100]
        let power = PowerReading(providing: "Battery Power", source: source, battery: ["Voltage": 12000, "Amperage": -1000])
        #expect(power.adapterWatts == 0 && power.systemWatts == 12)
        #expect(EnergyFlows(power, shares: []).columns == [[.battery], [.mac], []])
    }

    @Test func chargingBatteryIsFedByTheAdapter() {
        let power = PowerReading(adapterConnected: true, adapterWatts: 60,
                                 battery: .init(percent: 50, charging: true, watts: 20))
        let flows = EnergyFlows(power, shares: [EnergyShare(app: nil, share: 1)])
        #expect(flows.columns == [[.adapter], [.mac, .battery], [.other]])
        #expect(flows.links.map(\.weight) == [40, 20, 40])
    }

    @Test func sharesTopFiveThenOther() {
        let processes = (1...7).map { Self.process("app\($0)", energy: Double($0)) } + [Self.process("app7", energy: 1)]
        let shares = EnergyShare.top(processes)
        #expect(shares.map { $0.app?.key } == ["app7", "app6", "app5", "app4", "app3", nil])
        #expect(abs(shares.reduce(0) { $0 + $1.share } - 1) < 1e-9)
        #expect(EnergyShare.top([Self.process("a", energy: 0)]).isEmpty)
        // A query keeps the apps it matches; the rest go into Other.
        #expect(EnergyShare.top(processes, query: "app2").map { $0.app?.key } == ["app2", nil])
        #expect(EnergyShare.top(processes, query: "zzz").map { $0.app?.key } == [nil])
    }

    @Test func layoutHeightsAndBandsSum() {
        // Adapter 0 and battery 1 feed the Mac 2, which feeds apps 3 and 4.
        let links = [(from: 0, to: 2, weight: 30.0), (from: 1, to: 2, weight: 10.0), (from: 2, to: 3, weight: 25.0),
                     (from: 2, to: 4, weight: 15.0)]
        let (nodes, bands) = SankeyLayout.layout(columns: [0, 0, 1, 2, 2], links: links, size: CGSize(width: 300, height: 210),
                                                 nodeWidth: 10, gap: 10)
        #expect(nodes[2].height == 200 && nodes[2].minY == 5)
        #expect(nodes[0].height + nodes[1].height == 200 && nodes[1].minY == nodes[0].maxY + 10)
        #expect(bands[1].y1 == bands[0].y1 + bands[0].thickness)
        #expect(bands[3].y0 == bands[2].y0 + bands[2].thickness)
        #expect(bands[3].y0 + bands[3].thickness == Double(nodes[2].maxY))
        #expect(bands[0].x0 == 10 && bands[2].x1 == 290)
    }

    @Test func layoutWithZeroTotalOrOneSource() {
        let zero = SankeyLayout.layout(columns: [0, 1], links: [(from: 0, to: 1, weight: 0)], size: CGSize(width: 100, height: 100),
                                       nodeWidth: 10, gap: 10)
        #expect(zero.nodes.allSatisfy { $0.height == 0 && $0.minY == 50 } && zero.bands[0].thickness == 0)
        let one = SankeyLayout.layout(columns: [0, 1], links: [(from: 0, to: 1, weight: 1)], size: CGSize(width: 100, height: 100),
                                      nodeWidth: 10, gap: 10)
        #expect(one.nodes.allSatisfy { $0.height == 100 } && one.bands[0].thickness == 100)
    }

    @Test func spreadKeepsLabelsApartInside() {
        #expect(SankeyLayout.spread([0, 1, 2], spacing: 10, in: 0...100) == [0, 10, 20])
        #expect(SankeyLayout.spread([95, 99], spacing: 10, in: 0...100) == [90, 100])
    }
}

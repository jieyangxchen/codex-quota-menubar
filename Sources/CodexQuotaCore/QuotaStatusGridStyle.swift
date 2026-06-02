import Foundation

public enum QuotaStatusTextAlignment: Equatable, Sendable {
    case leading
    case center
}

public struct QuotaStatusGridStyle: Equatable, Sendable {
    public let columnWidth: Int
    public let itemHeight: Int
    public let labelFontSize: Int
    public let valueFontSize: Int
    public let lineGap: Double
    public let verticalAdjustment: Double
    public let labelOriginY: Double
    public let valueOriginY: Double
    public let horizontalAlignment: QuotaStatusTextAlignment
    public let horizontalPadding: Double

    public static let `default` = QuotaStatusGridStyle(
        columnWidth: 42,
        itemHeight: 24,
        labelFontSize: 9,
        valueFontSize: 11,
        lineGap: -3,
        verticalAdjustment: -1,
        labelOriginY: 10.5,
        valueOriginY: -1.5,
        horizontalAlignment: .center,
        horizontalPadding: 1
    )
}

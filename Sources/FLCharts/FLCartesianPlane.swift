//
//  FLCartesianPlane.swift
//  FLCharts
//
//  Created by Francesco Leoni on 18/01/22.
//

import UIKit

/// Defines a horizontal position.
public enum YPosition {
    case left
    case right
}

/// The cartesian plane on which the chart is plotted.
public class FLCartesianPlane: UIView, FLStylable {
    
    private struct Label {
        var text: String
        var size: CGSize
        var yPosition: CGFloat
    }

    /// The configuration of the chart.
    public var config: FLChartConfig = FLChartConfig() {
        didSet {
            updateConfigGranularityY()
        }
    }

    /// The data to show in the chart.
    private var chartData: FLChartData

    /// The margins of the chart.
    private var margin: UIEdgeInsets { config.margin }
        
    private var marginForAverageView: CGFloat = 70
    
    private let chartLayoutGuide = UILayoutGuide()
    
    internal var didUpdateChartLayoutGuide: (UILayoutGuide) -> Void = { _ in }
    
    internal let chartType: FLChart.PlotType
    
    /// The position of the y axis.
    public var yAxisPosition: YPosition = .left
    
    /// Whether to show the axes ticks.
    public var showTicks: Bool = true
    
    /// Whether to show the dash lines.
    public var showDashedLines: Bool = true
    
    /// Whether to show the average line.
    public var showAverageLine: Bool = false {
        didSet {
            if case .line = chartType, chartData.numberOfValues > 1 {
                showAverageLine = false
            }
        }
    }
            
    // MARK: - Inits
        
    /// Creates a cartesian plane with the provided chart data.
    internal init(data: FLChartData, type: FLChart.PlotType) {
        self.chartData = data
        self.chartType = type
        super.init(frame: .zero)
        self.config.granularityY = data.defaultYGranularity(forType: type)
        self.backgroundColor = .clear
        
        self.addLayoutGuide(chartLayoutGuide)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Updates the values of the chart.
    internal func updateData(_ data: [PlotableData]) {
        self.chartData.dataEntries = data
        self.updateConfigGranularityY()
        self.setNeedsDisplay()
    }

    // MARK: - Configurations
        
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawAxes(in: context, rect: rect)
    }
        
    private func drawAxes(in context: CGContext, rect: CGRect) {
        context.saveGState()
        
        let halfAxesWidth = config.axesLines.lineWidth / 2

        var chartLeft: CGFloat { rect.minX + margin.left }
        var chartRight: CGFloat { rect.maxX - margin.right }
        let chartTop = rect.minY + margin.top - halfAxesWidth
        let chartBottom = rect.maxY - margin.bottom + halfAxesWidth

        var chartWidth: CGFloat { chartRight - chartLeft }
        let chartHeight = chartBottom - chartTop
        
        var chartTopLeft: CGPoint { CGPoint(x: chartLeft, y: chartTop) }
        var chartTopRight: CGPoint { CGPoint(x: chartRight, y: chartTop) }
        var chartBottomLeft: CGPoint { CGPoint(x: chartLeft, y: chartBottom) }
        var chartBottomRight: CGPoint { CGPoint(x: chartRight, y: chartBottom) }
        
        /* Paths */
        
        let axesLines = CGMutablePath()
        let ticksLines = CGMutablePath()
        let dashedLines = CGMutablePath()

        /* Y Axis labels and ticks */

        let dataMinValue: CGFloat = 0
        var dataMaxValue: CGFloat = chartData.maxYValue(forType: chartType) ?? 0
        var step = config.granularityY
        let tickLabelSpacing: CGFloat = 4
        var maxYLabelWidth: CGFloat = 0
        var labelsYAxis: [Label] = []
        
        if dataMaxValue == 0 {
            dataMaxValue = 1
            step = 1
        }
        
        for value in stride(from: dataMinValue, through: dataMaxValue, by: step) {
            if value != 0 {
                let chartTickY = yPosition(forValue: value)
                
                let text = "\(Int(value))"
                let labelSize = text.size(withSystemFontSize: config.axesLabels.font.pointSize)
                
                if labelSize.width > maxYLabelWidth {
                    maxYLabelWidth = labelSize.width
                }
                
                labelsYAxis.append(Label(text: text, size: labelSize, yPosition: chartTickY))
            }
        }
        
        // This prevents the last label to overlap the max label.
        if let lastLabel = labelsYAxis.last, lastLabel.yPosition - chartTop > 15 {
            let text = "\(Int(dataMaxValue))"
            let labelSize = text.size(withSystemFontSize: config.axesLabels.font.pointSize)
            labelsYAxis.append(Label(text: text, size: labelSize, yPosition: chartTop))
            
            if labelSize.width > maxYLabelWidth {
                maxYLabelWidth = labelSize.width
            }
        }
        
        config.setMargin(for: yAxisPosition, horizontalMargin: maxYLabelWidth + config.tick.lineLength + tickLabelSpacing)
                        
        for label in labelsYAxis {
            let yPosition = label.yPosition
            
            drawLabel(label)

            if showTicks {
                if yAxisPosition == .left {
                    ticksLines.addLines(between: [CGPoint(x: chartLeft - config.tick.lineLength, y: yPosition),
                                                  CGPoint(x: chartLeft, y: yPosition)])
                } else {
                    ticksLines.addLines(between: [CGPoint(x: chartRight + config.tick.lineLength, y: yPosition),
                                                  CGPoint(x: chartRight, y: yPosition)])
                }
            }
                        
            if showDashedLines {
                dashedLines.addLines(between: [CGPoint(x: chartLeft, y: yPosition),
                                               CGPoint(x: chartRight, y: yPosition)])
            }
        }
        
        drawAverageLine()

        /* X Axis */
        
        if case .line = chartType {
            let entriesCount = chartData.dataEntries.count - 1
            
            var usefulChartWidth = chartWidth - marginForAverageView
            var startXPosition = yAxisPosition == .left ? 0 : marginForAverageView
            
            if !showAverageLine {
                usefulChartWidth = chartWidth
                startXPosition = 0
            }
            
            let step = usefulChartWidth / CGFloat(entriesCount)
            
            for (index, x) in stride(from: startXPosition, through: chartWidth, by: step).enumerated() {
                guard index.isMultiple(of: config.granularityX) else { continue }
                
                let percentageOfTotal = x / chartWidth * 100
                let viewWidth = chartWidth * percentageOfTotal / 100
                let XPosition = margin.left + viewWidth
                
                // Removes last x axes label when y axes if on the left.
                if index >= entriesCount, case .left = yAxisPosition {
                    continue
                }
                
                // Removes first x axes label when y axes if on the right.
                if x == 0, case .right = yAxisPosition {
                    continue
                }
                
                let text = chartData.dataEntries[index].name
                let labelSize = text.size(withSystemFontSize: config.axesLabels.font.pointSize)
                
                let labelDrawPoint = CGPoint(
                    x: XPosition - (labelSize.width / 2),
                    y: chartBottom + 10)
                
                drawLabel(text: text, inPoint: labelDrawPoint)
                
                if showTicks, x != 0 {
                    ticksLines.addLines(between: [CGPoint(x: XPosition, y: chartBottom),
                                                  CGPoint(x: XPosition, y: chartBottom + config.tick.lineLength)])
                }

                if showDashedLines {
                    dashedLines.addLines(between: [CGPoint(x: XPosition, y: chartTop),
                                                   CGPoint(x: XPosition, y: chartBottom)])
                }
            }
        }
        
        /* Axes lines */
        
        if yAxisPosition == .left {
            axesLines.addLines(between: [chartTopLeft,
                                         chartBottomLeft,
                                         chartBottomRight])
        } else {
            axesLines.addLines(between: [chartTopRight,
                                         chartBottomRight,
                                         chartBottomLeft])
        }
        
        context.setStrokeColor(config.axesLines.color.cgColor)
        context.setLineWidth(config.axesLines.lineWidth)
        context.addPath(axesLines)
        context.strokePath()
        
        context.setStrokeColor(config.tick.color.cgColor)
        context.setLineWidth(config.tick.lineWidth)
        context.addPath(ticksLines)
        context.strokePath()

        context.setStrokeColor(config.dashedLines.color.cgColor)
        context.setLineWidth(config.dashedLines.lineWidth)
        context.setLineDash(phase: 0, lengths: [config.dashedLines.dashWidth])
        context.addPath(dashedLines)
        context.strokePath()
        
        /// Whenever you change a graphics context you should save it prior and restore it after
        /// if we were using a context other than `draw(_:)` we would have to also end the graphics context.
        context.restoreGState()
        
        updateChartLayoutGuide()
        
        func yPosition(forValue value: CGFloat) -> CGFloat {
            let percentageOfTotal = value / dataMaxValue * 100
            let viewHeight = chartHeight * percentageOfTotal / 100
            return chartHeight - viewHeight + chartTop
        }
        
        func drawLabel(_ label: Label) {
            var labelXPosition: CGFloat = 0
            
            if yAxisPosition == .left {
                labelXPosition = chartLeft - config.tick.lineLength - tickLabelSpacing - label.size.width
            } else {
                labelXPosition = chartRight + config.tick.lineLength + tickLabelSpacing
            }
            
            let labelDrawPoint = CGPoint(x: labelXPosition, y: label.yPosition - (label.size.height / 2))
            
            drawLabel(text: label.text, inPoint: labelDrawPoint)
        }
        
        func drawLabel(text: String, inPoint point: CGPoint) {
            (text as NSString).draw(at: point,
                                    withAttributes: [.font: config.axesLabels.font,
                                                     .foregroundColor: config.axesLabels.color])
        }

        func xPositionForAverageLabel(_ label: UILabel) -> CGFloat {
            if yAxisPosition == .left {
                return chartRight - label.intrinsicWidth - 5
            } else {
                return chartLeft + 5
            }
        }
        
        func drawAverageLine() {
            if showAverageLine {
                let averageLineY = yPosition(forValue: chartData.average)
                let spacingFromLine: CGFloat = 2
                
                let averageLabel = UILabel()
                averageLabel.text = chartData.formattedAverage
                averageLabel.font = config.averageView.primaryFont
                averageLabel.textColor = config.averageView.primaryColor
                let averageLabelSize = averageLabel.intrinsicContentSize
                averageLabel.frame = CGRect(x: xPositionForAverageLabel(averageLabel),
                                            y: averageLineY - averageLabelSize.height - spacingFromLine,
                                            width: averageLabelSize.width,
                                            height: averageLabelSize.height)
                addSubview(averageLabel)
                
                let unitOfMeasureLabel = UILabel()
                unitOfMeasureLabel.text = "avg. \(chartData.unitOfMeasure)"
                unitOfMeasureLabel.font = config.averageView.secondaryFont
                unitOfMeasureLabel.textColor = config.averageView.secondaryColor
                let unitOfMeasureLabelSize = unitOfMeasureLabel.intrinsicContentSize
                unitOfMeasureLabel.frame = CGRect(x: xPositionForAverageLabel(unitOfMeasureLabel),
                                                  y: averageLineY + spacingFromLine,
                                                  width: unitOfMeasureLabelSize.width,
                                                  height: unitOfMeasureLabelSize.height)
                addSubview(unitOfMeasureLabel)
                
                let line = UIView()
                line.backgroundColor = config.averageView.lineColor
                line.frame = CGRect(x: chartLeft, y: averageLineY, width: chartWidth, height: config.averageView.lineWidth)
                addSubview(line)
                
                marginForAverageView = max(averageLabelSize.width, unitOfMeasureLabelSize.width) + 15
            }
        }
    }
    
    private func updateChartLayoutGuide() {
        var leadingConstant: CGFloat = 0
        var trailingConstant: CGFloat = 0

        switch yAxisPosition {
        case .left:
            leadingConstant = margin.left + config.axesLines.lineWidth
            trailingConstant = showAverageLine ? -marginForAverageView - margin.right : -margin.right
            
        case .right:
            leadingConstant = showAverageLine ? marginForAverageView + margin.left : margin.left
            trailingConstant = -margin.right - config.axesLines.lineWidth
        }

        NSLayoutConstraint.activate([
            chartLayoutGuide.topAnchor.constraint(equalTo: topAnchor, constant: margin.top),
            chartLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingConstant),
            chartLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
            chartLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: trailingConstant)
        ])
        
        didUpdateChartLayoutGuide(chartLayoutGuide)
    }
    
    private func updateConfigGranularityY() {
        if config.granularityY == 0 {
            config.granularityY = chartData.defaultYGranularity(forType: chartType)
        }
    }
}
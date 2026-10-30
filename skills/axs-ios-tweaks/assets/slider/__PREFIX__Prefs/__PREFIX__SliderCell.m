#import "__PREFIX__SliderCell.h"
#import <UIKit/UIKit.h>

@interface __PREFIX__SliderCell ()
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation __PREFIX__SliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier specifier:specifier];
    if (self) {
        _slider = [[UISlider alloc] initWithFrame:CGRectZero];
        [_slider addTarget:self action:@selector(__SYMBOL___sliderMoved:)
          forControlEvents:UIControlEventValueChanged];
        [_slider addTarget:self action:@selector(__SYMBOL___sliderCommitted:)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self.contentView addSubview:_slider];
        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
        _valueLabel.textColor = [UIColor secondaryLabelColor];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.6;
        [self.contentView addSubview:_valueLabel];
        self.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self __SYMBOL___reloadState];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self __SYMBOL___reloadState];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.handler = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat available = MAX(0.0, width - 32.0);
    CGFloat valueWidth = MIN(52.0, available * 0.25);
    CGFloat titleWidth = MIN(110.0, available * 0.32);
    CGFloat sliderX = 16.0 + titleWidth + 8.0;
    CGFloat valueX = MAX(sliderX, width - 16.0 - valueWidth);
    self.textLabel.frame = CGRectMake(16.0, 0, titleWidth, height);
    self.slider.frame = CGRectMake(sliderX, MAX(0.0, (height - 31.0) / 2.0),
                                  MAX(0.0, valueX - 8.0 - sliderX), 31.0);
    self.valueLabel.frame = CGRectMake(valueX, 0, valueWidth, height);
}

- (void)__SYMBOL___reloadState {
    self.textLabel.text = self.specifier.name ?: @"";
    self.slider.accessibilityLabel = self.textLabel.text;
    double minimum = [[self.specifier propertyForKey:@"min"] doubleValue];
    double maximum = [[self.specifier propertyForKey:@"max"] doubleValue];
    if (!isfinite(minimum)) minimum = 0.0;
    if (!isfinite(maximum) || maximum <= minimum) maximum = minimum + 1.0;
    self.slider.minimumValue = minimum;
    self.slider.maximumValue = maximum;
    id initial = [self.specifier propertyForKey:@"default"];
    double value = self.handler ? [self.handler __SYMBOL___sliderValueForSpecifier:self.specifier]
                               : [initial doubleValue];
    if (!isfinite(value)) value = minimum;
    self.slider.value = fmax(minimum, fmin(maximum, value));
    [self __SYMBOL___updateLabel];
}

- (void)__SYMBOL___updateLabel {
    NSString *value = [NSString stringWithFormat:@"%.1f", self.slider.value];
    self.valueLabel.text = value;
    self.slider.accessibilityValue = value;
}

- (void)__SYMBOL___sliderMoved:(UISlider *)sender {
    [self __SYMBOL___updateLabel];
    // VoiceOver adjustments do not necessarily emit touch-up events.
    if (UIAccessibilityIsVoiceOverRunning()) {
        [self __SYMBOL___sliderCommitted:sender];
    }
}

- (void)__SYMBOL___sliderCommitted:(UISlider *)sender {
    [self __SYMBOL___updateLabel];
    [self.handler __SYMBOL___setSliderValue:sender.value specifier:self.specifier];
}

@end

#pragma once

#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#include <math.h>

@protocol __PREFIX__SliderCellHandler <NSObject>
- (double)__SYMBOL___sliderValueForSpecifier:(PSSpecifier *)specifier;
- (void)__SYMBOL___setSliderValue:(double)value specifier:(PSSpecifier *)specifier;
@end

@interface __PREFIX__SliderCell : PSTableCell
@property (nonatomic, weak) id<__PREFIX__SliderCellHandler> handler;
- (void)__SYMBOL___reloadState;
@end

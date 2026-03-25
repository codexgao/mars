// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

#import "XLogConfig.h"

@implementation XLogConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode          = XLogAppenderModeAsync;
        _logdir        = @"";
        _nameprefix    = @"";
        _pubKey        = nil;
        _compressMode  = XLogCompressModeZlib;
        _compressLevel = 0;
        _cachedir      = nil;
        _cacheDays     = 0;
    }
    return self;
}

@end

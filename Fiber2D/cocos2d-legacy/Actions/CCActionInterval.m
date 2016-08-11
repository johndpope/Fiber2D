/*
 * Cocos2D-SpriteBuilder: http://cocos2d.spritebuilder.com
 *
 * Copyright (c) 2008-2011 Ricardo Quesada
 * Copyright (c) 2011 Zynga Inc.
 * Copyright (c) 2013-2014 Cocos2D Authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */


#import "ccTypes.h"
#import "CCAction_Private.h"

#import "CCActionInterval.h"
#import "CCActionInstant.h"

#import "Fiber2D-Swift.h"
//
// IntervalAction
//
#pragma mark - CCIntervalAction
@implementation CCActionInterval {
    CCTime _elapsed;
    BOOL _firstTick;
}

@synthesize elapsed = _elapsed;

-(id) init
{
	NSAssert(NO, @"IntervalActionInit: Init not supported. Use InitWithDuration");
	return nil;
}

+(instancetype) actionWithDuration: (CCTime) d
{
	return [[self alloc] initWithDuration:d ];
}

-(id) initWithDuration: (CCTime) d
{
	if( (self=[super init]) ) {
		_duration = d;

		// prevent division by 0
		// This comparison could be in step:, but it might decrease the performance
		// by 3% in heavy based action games.
		if( _duration == 0 )
			_duration = FLT_EPSILON;
		_elapsed = 0;
		_firstTick = YES;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] ];
	return copy;
}

- (BOOL) isDone
{
	return (_elapsed >= _duration);
}

-(void) step: (CCTime) dt
{
	if( _firstTick ) {
		_firstTick = NO;
		_elapsed = 0;
	} else
		_elapsed += dt;


	[self update: MAX(0,					// needed for rewind. elapsed could be negative
					  MIN(1, _elapsed/
						  MAX(_duration,FLT_EPSILON)	// division by 0
						  )
					  )
	 ];
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	_elapsed = 0.0f;
	_firstTick = YES;
}

- (CCActionInterval*) reverse
{
	NSAssert(NO, @"CCIntervalAction: reverse not implemented.");
	return nil;
}
@end

//
// Sequence
//
#pragma mark - CCSequence
@implementation CCActionSequence {
    CCActionFiniteTime *_actions[2];
    CCTime _split;
    int _last;
}

+(instancetype) actions: (CCActionFiniteTime*) action1, ...
{
	va_list args;
	va_start(args, action1);

	id ret = [self actions:action1 vaList:args];

	va_end(args);

	return  ret;
}

+(instancetype)actions:(CCActionFiniteTime*)action1 vaList:(va_list)args
{
    CCActionFiniteTime *now = nil;
    CCActionFiniteTime *prev = action1;

    while(action1){
        now = va_arg(args, CCActionFiniteTime *);
        if(now){
            prev = [self actionOne:prev two:now];
        } else {
            break;
        }
    }

    return (CCActionSequence *)prev;
}


+(instancetype)actionWithArray:(NSArray *)actions
{
    CCActionFiniteTime *prev = actions[0];

    for(NSUInteger i = 1; i < actions.count; i++){
        prev = [self actionOne:prev two:actions[i]];
    }

    return (CCActionSequence *)prev;
}

-(id) initWithArray:(NSArray *)actions
{
    // this is backwards because it's "safer" as a quick Swift fix for v3.4
    return [CCActionSequence actionWithArray:actions];
}

+(instancetype) actionOne: (CCActionFiniteTime*) one two: (CCActionFiniteTime*) two
{
	return [[self alloc] initOne:one two:two ];
}

-(id) initOne: (CCActionFiniteTime*) one two: (CCActionFiniteTime*) two
{
	NSAssert( one!=nil && two!=nil, @"Sequence: arguments must be non-nil");
	// NSAssert( one!=_actions[0] && one!=_actions[1], @"Sequence: re-init using the same parameters is not supported");
	// NSAssert( two!=_actions[1] && two!=_actions[0], @"Sequence: re-init using the same parameters is not supported");
	
	CCTime d = [one duration] + [two duration];
	
	if( (self=[super initWithDuration: d]) ) {
		
		// XXX: Supports re-init without leaking. Fails if one==_one || two==_two
		
		_actions[0] = one;
		_actions[1] = two;
	}
	
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone:zone] initOne:[_actions[0] copy] two:[_actions[1] copy] ];
	return copy;
}


-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	_split = [_actions[0] duration] / MAX(_duration, FLT_EPSILON);
	_last = -1;
}

-(void) stop
{
	// Issue #1305
	if( _last != - 1)
		[_actions[_last] stop];

	[super stop];
}

-(void) update: (CCTime) t
{

	int found = 0;
	CCTime new_t = 0.0f;
	
	if( t < _split ) {
		// action[0]
		found = 0;
		if( _split != 0 )
			new_t = t / _split;
		else
			new_t = 1;

	} else {
		// action[1]
		found = 1;
		if ( _split == 1 )
			new_t = 1;
		else
			new_t = (t-_split) / (1 - _split );
	}
	
	if ( found==1 ) {
		
		if( _last == -1 ) {
			// action[0] was skipped, execute it.
			[_actions[0] startWithTarget:_target];
			[_actions[0] update:1.0f];
			[_actions[0] stop];
		}
		else if( _last == 0 )
		{
			// switching to action 1. stop action 0.
			[_actions[0] update: 1.0f];
			[_actions[0] stop];
		}
	}
	else if(found==0 && _last==1 )
	{
		// Reverse mode ?
		// XXX: Bug. this case doesn't contemplate when _last==-1, found=0 and in "reverse mode"
		// since it will require a hack to know if an action is on reverse mode or not.
		// "step" should be overriden, and the "reverseMode" value propagated to inner Sequences.
		[_actions[1] update:0];
		[_actions[1] stop];
	}
	
	// Last action found and it is done.
	if( found == _last && [_actions[found] isDone] ) {
		return;
	}

	// New action. Start it.
	if( found != _last )
		[_actions[found] startWithTarget:_target];
	
	[_actions[found] update: new_t];
	_last = found;
}

- (CCActionInterval *) reverse
{
	return [[self class] actionOne: [_actions[1] reverse] two: [_actions[0] reverse ] ];
}
@end

//
// Repeat
//
#pragma mark - CCRepeat
@implementation CCActionRepeat {
    NSUInteger _times;
    NSUInteger _total;
    CCTime _nextDt;
    BOOL _isActionInstant;
    CCActionFiniteTime *_innerAction;
}

+(instancetype) actionWithAction:(CCActionFiniteTime*)action times:(NSUInteger)times
{
	return [[self alloc] initWithAction:action times:times];
}

-(id) initWithAction:(CCActionFiniteTime*)action times:(NSUInteger)times
{
	CCTime d = [action duration] * times;

	if( (self=[super initWithDuration: d ]) ) {
		_times = times;
		self.innerAction = action;
		_isActionInstant = ([action isKindOfClass:[CCActionInstant class]]) ? YES : NO;

		//a instant action needs to be executed one time less in the update method since it uses startWithTarget to execute the action
		if (_isActionInstant) _times -=1;
		_total = 0;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone:zone] initWithAction:[_innerAction copy] times:_times];
	return copy;
}


-(void) startWithTarget:(id)aTarget
{
	_total = 0;
	_nextDt = [_innerAction duration]/_duration;
	[super startWithTarget:aTarget];
	[_innerAction startWithTarget:aTarget];
}

-(void) stop
{
    [_innerAction stop];
	[super stop];
}


// issue #80. Instead of hooking step:, hook update: since it can be called by any
// container action like CCRepeat, CCSequence, CCEase, etc..
-(void) update:(CCTime) dt
{
	if (dt >= _nextDt)
	{
		while (dt > _nextDt && _total < _times)
		{
			[_innerAction update:1.0];
			_total++;

			[_innerAction stop];
			[_innerAction startWithTarget:_target];
			_nextDt += [_innerAction duration]/_duration;
		}
		
		// fix for issue #1288, incorrect end value of repeat
		if(dt >= 1.0 && _total < _times) 
		{
			_total++;
		}
		
		// don't set a instantaction back or update it, it has no use because it has no duration
		if (!_isActionInstant)
		{
			if (_total == _times)
			{
				[_innerAction update:1.0];
				[_innerAction stop];
			}
			else
			{
				// issue #390 prevent jerk, use right update
				[_innerAction update:dt - (_nextDt - _innerAction.duration/_duration)];
			}
		}
	}
	else
	{
		[_innerAction update:fmod(dt * _times, 1.0)];
	}
}

-(BOOL) isDone
{
	return ( _total == _times );
}

- (CCActionInterval *) reverse
{
	return [[self class] actionWithAction:[_innerAction reverse] times:_times];
}
@end

//
// Spawn
//
#pragma mark - CCSpawn

@implementation CCActionSpawn {
    CCActionFiniteTime *_one;
    CCActionFiniteTime *_two;
}

+(instancetype) actions: (CCActionFiniteTime*) action1, ...
{
	va_list args;
	va_start(args, action1);

	id ret = [self actions:action1 vaList:args];

	va_end(args);
	return ret;
}

+(instancetype) actions: (CCActionFiniteTime*) action1 vaList:(va_list)args
{
    CCActionFiniteTime *now = nil;
    CCActionFiniteTime *prev = action1;

    while(action1){
        now = va_arg(args,CCActionFiniteTime*);
        if(now){
            prev = [self actionOne: prev two: now];
        } else {
            break;
        }
    }

    return (CCActionSpawn *)prev;
}

+(instancetype) actionWithArray: (NSArray*) actions
{
    CCActionFiniteTime *prev = actions[0];

    for (NSUInteger i = 1; i < [actions count]; i++){
        prev = [self actionOne:prev two:actions[i]];
    }

    return (CCActionSpawn *)prev;
}

-(id) initWithArray: (NSArray*) actions
{
    // this is backwards because it's "safer" as a quick Swift fix for v3.4
    return [CCActionSpawn actionWithArray:actions];
}

+(instancetype) actionOne: (CCActionFiniteTime*) one two: (CCActionFiniteTime*) two
{
	return [[self alloc] initOne:one two:two ];
}

-(id) initOne: (CCActionFiniteTime*) one two: (CCActionFiniteTime*) two
{
	NSAssert( one!=nil && two!=nil, @"Spawn: arguments must be non-nil");
	NSAssert( one!=_one && one!=_two, @"Spawn: reinit using same parameters is not supported");
	NSAssert( two!=_two && two!=_one, @"Spawn: reinit using same parameters is not supported");

	CCTime d1 = [one duration];
	CCTime d2 = [two duration];

	if( (self=[super initWithDuration: MAX(d1,d2)] ) ) {

		// XXX: Supports re-init without leaking. Fails if one==_one || two==_two

		_one = one;
		_two = two;

		if( d1 > d2 )
			_two = [CCActionSequence actionOne:two two:[CCActionDelay actionWithDuration: (d1-d2)] ];
		else if( d1 < d2)
			_one = [CCActionSequence actionOne:one two: [CCActionDelay actionWithDuration: (d2-d1)] ];

	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initOne: [_one copy] two: [_two copy] ];
	return copy;
}


-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	[_one startWithTarget:_target];
	[_two startWithTarget:_target];
}

-(void) stop
{
	[_one stop];
	[_two stop];
	[super stop];
}

-(void) update: (CCTime) t
{
	[_one update:t];
	[_two update:t];
}

- (CCActionInterval *) reverse
{
	return [[self class] actionOne: [_one reverse] two: [_two reverse ] ];
}
@end

//
// RotateTo
//
#pragma mark - CCRotateTo

@implementation CCActionRotateTo {
    float _dstAngleX;
    float _startAngleX;
    float _diffAngleX;

    float _dstAngleY;
    float _startAngleY;
    float _diffAngleY;

    bool _rotateX;
    bool _rotateY;

    bool _simple;
}

+(instancetype) actionWithDuration: (CCTime) t angle:(float) a
{
	return [[self alloc] initWithDuration:t angle:a simple:NO];
}

+(instancetype) actionWithDuration: (CCTime) t angle:(float) a simple:(bool)simple
{
	return [[self alloc] initWithDuration:t angle:a simple:simple];
}

-(id) initWithDuration: (CCTime) t angle:(float) a
{
	return [self initWithDuration:t angle:a simple:NO];
}

-(id) initWithDuration: (CCTime) t angle:(float) a simple:(bool) simple
{
	if( (self=[super initWithDuration: t]) ) {
		_dstAngleX = _dstAngleY = a;
        _simple    = simple;
    }

	return self;
}

+(instancetype) actionWithDuration: (CCTime) t angleX:(float) aX angleY:(float) aY
{
	return [[self alloc] initWithDuration:t angleX:aX angleY:aY ];
}

-(id) initWithDuration: (CCTime) t angleX:(float) aX angleY:(float) aY
{
	if( (self=[super initWithDuration: t]) ){
		_dstAngleX = aX;
        _dstAngleY = aY;
        _rotateX   = YES;
        _rotateY   = YES;
    }
	return self;
}

+(instancetype) actionWithDuration: (CCTime) t angleX:(float) aX
{
	return [[self alloc] initWithDuration:t angleX:aX];
}

-(id) initWithDuration: (CCTime) t angleX:(float) aX
{
	if( (self=[super initWithDuration: t]) ){
		_dstAngleX = aX;
        _rotateX   = YES;
    }
	return self;
}

+(instancetype) actionWithDuration: (CCTime) t angleY:(float) aY
{
	return [[self alloc] initWithDuration:t angleY:aY];
}

-(id) initWithDuration: (CCTime) t angleY:(float) aY
{
	if( (self=[super initWithDuration: t]) ){
		_dstAngleY = aY;
        _rotateY   = YES;
    }
	return self;
}


-(id) copyWithZone: (NSZone*) zone
{

    if(_rotateX && _rotateY) {
        return [[[self class] allocWithZone: zone] initWithDuration:[self duration] angleX:_dstAngleX angleY:_dstAngleY];
    } else if (_rotateX) {
        return [[[self class] allocWithZone: zone] initWithDuration:[self duration] angleX:_dstAngleX];
    } else if (_rotateY) {
        return [[[self class] allocWithZone: zone] initWithDuration:[self duration] angleY:_dstAngleY];
    } else if (_simple) {
        return [[[self class] allocWithZone: zone] initWithDuration:[self duration] angle:_dstAngleX simple:YES];
    } else {
        return [[[self class] allocWithZone: zone] initWithDuration:[self duration] angle:_dstAngleX];
    }
}

-(void) startWithTarget:(Node *)aTarget
{
	[super startWithTarget:aTarget];
    
    // Simple Rotation (Support SpriteBuilder)
    if(_simple) {
        _startAngleX = _startAngleY = [(Node*)_target rotation];
        _diffAngleX = _dstAngleX - _startAngleX;
        _diffAngleY = _dstAngleY - _startAngleY;
        return;
    }

    //Calculate X
	_startAngleX = [_target rotationalSkewX];
	if (_startAngleX > 0)
		_startAngleX = fmodf(_startAngleX, 360.0f);
	else
		_startAngleX = fmodf(_startAngleX, -360.0f);

	_diffAngleX = _dstAngleX - _startAngleX;
	if (_diffAngleX > 180)
		_diffAngleX -= 360;
	if (_diffAngleX < -180)
		_diffAngleX += 360;
  
	
   //Calculate Y: It's duplicated from calculating X since the rotation wrap should be the same
	_startAngleY = [_target rotationalSkewY];
	if (_startAngleY > 0)
		_startAngleY = fmodf(_startAngleY, 360.0f);
	else
		_startAngleY = fmodf(_startAngleY, -360.0f);
  
	_diffAngleY = _dstAngleY - _startAngleY;
	if (_diffAngleY > 180)
		_diffAngleY -= 360;
	if (_diffAngleY < -180)
		_diffAngleY += 360;
}
-(void) update: (CCTime) t
{
    // added to support overriding setRotation only
    if ((_startAngleX == _startAngleY) && (_diffAngleX == _diffAngleY))
    {
        [(Node *)_target setRotation:(_startAngleX + (_diffAngleX * t))];
    }
    else
    {
        if(_rotateX)
            [_target setRotationalSkewX: _startAngleX + _diffAngleX * t];
        if(_rotateY)
            [_target setRotationalSkewY: _startAngleY + _diffAngleY * t];
    }
}
@end


//
// RotateBy
//
#pragma mark - RotateBy

@implementation CCActionRotateBy {
    float _angleX;
    float _startAngleX;
    float _angleY;
    float _startAngleY;
}

+(instancetype) actionWithDuration: (CCTime) t angle:(float) a
{
	return [[self alloc] initWithDuration:t angle:a ];
}

-(id) initWithDuration: (CCTime) t angle:(float) a
{
	if( (self=[super initWithDuration: t]) )
		_angleX = _angleY = a;

	return self;
}

+(instancetype) actionWithDuration: (CCTime) t angleX:(float) aX angleY:(float) aY
{
	return [[self alloc] initWithDuration:t angleX:aX angleY:aY ];
}

-(id) initWithDuration: (CCTime) t angleX:(float) aX angleY:(float) aY
{
	if( (self=[super initWithDuration: t]) ){
		_angleX = aX;
        _angleY = aY;
    }
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] angleX: _angleX angleY:_angleY];
	return copy;
}

-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	_startAngleX = [_target rotationalSkewX];
	_startAngleY = [_target rotationalSkewY];
}

-(void) update: (CCTime) t
{
	// XXX: shall I add % 360
    // added to support overriding setRotation only
    if ((_startAngleX == _startAngleY) && (_angleX == _angleY))
    {
        [(Node *)_target setRotation:(_startAngleX + (_angleX * t))];
    }
    else
    {
        [_target setRotationalSkewX: (_startAngleX + _angleX * t )];
        [_target setRotationalSkewY: (_startAngleY + _angleY * t )];
    }
}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration angleX:-_angleX angleY:-_angleY];
}

@end


//
// SkewTo
//
#pragma mark - CCSkewTo

@implementation CCActionSkewTo {
    @protected
    float _skewX;
    float _skewY;
    float _startSkewX;
    float _startSkewY;
    float _endSkewX;
    float _endSkewY;
    float _deltaX;
    float _deltaY;
}

+(instancetype) actionWithDuration:(CCTime)t skewX:(float)sx skewY:(float)sy
{
	return [[self alloc] initWithDuration: t skewX:sx skewY:sy];
}

-(id) initWithDuration:(CCTime)t skewX:(float)sx skewY:(float)sy
{
	if( (self=[super initWithDuration:t]) ) {
		_endSkewX = sx;
		_endSkewY = sy;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] skewX:_endSkewX skewY:_endSkewY];
	return copy;
}

-(void) startWithTarget:(Node *)aTarget
{
	[super startWithTarget:aTarget];

	_startSkewX = [_target skewX];

	if (_startSkewX > 0)
		_startSkewX = fmodf(_startSkewX, 180.0f);
	else
		_startSkewX = fmodf(_startSkewX, -180.0f);

	_deltaX = _endSkewX - _startSkewX;

	if ( _deltaX > 180 ) {
		_deltaX -= 360;
	}
	if ( _deltaX < -180 ) {
		_deltaX += 360;
	}

	_startSkewY = [_target skewY];

	if (_startSkewY > 0)
		_startSkewY = fmodf(_startSkewY, 360.0f);
	else
		_startSkewY = fmodf(_startSkewY, -360.0f);

	_deltaY = _endSkewY - _startSkewY;

	if ( _deltaY > 180 ) {
		_deltaY -= 360;
	}
	if ( _deltaY < -180 ) {
		_deltaY += 360;
	}
}

-(void) update: (CCTime) t
{
	[_target setSkewX: (_startSkewX + _deltaX * t ) ];
	[_target setSkewY: (_startSkewY + _deltaY * t ) ];
}

@end

//
// CCSkewBy
//
#pragma mark - CCSkewBy

@implementation CCActionSkewBy

-(id) initWithDuration:(CCTime)t skewX:(float)deltaSkewX skewY:(float)deltaSkewY
{
	if( (self=[super initWithDuration:t skewX:deltaSkewX skewY:deltaSkewY]) ) {
		_skewX = deltaSkewX;
		_skewY = deltaSkewY;
	}
	return self;
}

-(void) startWithTarget:(Node *)aTarget
{
	[super startWithTarget:aTarget];
	_deltaX = _skewX;
	_deltaY = _skewY;
	_endSkewX = _startSkewX + _deltaX;
	_endSkewY = _startSkewY + _deltaY;
}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration skewX:-_skewX skewY:-_skewY];
}
@end


#pragma mark - CCBezierBy

// Bezier cubic formula:
//	((1 - t) + t)3 = 1
// Expands to…
//   (1 - t)3 + 3t(1-t)2 + 3t2(1 - t) + t3 = 1
static inline CGFloat bezierat( float a, float b, float c, float d, CCTime t )
{
	return (powf(1-t,3) * a +
			3*t*(powf(1-t,2))*b +
			3*powf(t,2)*(1-t)*c +
			powf(t,3)*d );
}


//
// ScaleTo
//
#pragma mark - CCScaleTo
@implementation CCActionScaleTo {
    @protected
    float _scaleX;
    float _scaleY;
    float _startScaleX;
    float _startScaleY;
    float _endScaleX;
    float _endScaleY;
    float _deltaX;
    float _deltaY;
}

+(instancetype) actionWithDuration: (CCTime) t scale:(float) s
{
	return [[self alloc] initWithDuration: t scale:s];
}

-(id) initWithDuration: (CCTime) t scale:(float) s
{
	if( (self=[super initWithDuration: t]) ) {
		_endScaleX = s;
		_endScaleY = s;
	}
	return self;
}

+(instancetype) actionWithDuration: (CCTime) t scaleX:(float)sx scaleY:(float)sy
{
	return [[self alloc] initWithDuration: t scaleX:sx scaleY:sy];
}

-(id) initWithDuration: (CCTime) t scaleX:(float)sx scaleY:(float)sy
{
	if( (self=[super initWithDuration: t]) ) {
		_endScaleX = sx;
		_endScaleY = sy;
	}
	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] scaleX:_endScaleX scaleY:_endScaleY];
	return copy;
}

-(void) startWithTarget:(Node *)aTarget
{
	[super startWithTarget:aTarget];
	_startScaleX = [_target scaleX];
	_startScaleY = [_target scaleY];
	_deltaX = _endScaleX - _startScaleX;
	_deltaY = _endScaleY - _startScaleY;
}

-(void) update: (CCTime) t
{
    // added to support overriding setScale only
    if ((_startScaleX == _startScaleY) && (_endScaleX == _endScaleY))
    {
        [(Node *)_target setScale:(_startScaleX + (_deltaX * t))];
    }
    else
    {
        [_target setScaleX: (_startScaleX + _deltaX * t ) ];
        [_target setScaleY: (_startScaleY + _deltaY * t ) ];
    }
}
@end

//
// ScaleBy
//
#pragma mark - CCScaleBy
@implementation CCActionScaleBy

-(void) startWithTarget:(Node *)aTarget
{
	[super startWithTarget:aTarget];
	_deltaX = _startScaleX * _endScaleX - _startScaleX;
	_deltaY = _startScaleY * _endScaleY - _startScaleY;
}

-(CCActionInterval*) reverse
{
	return [[self class] actionWithDuration:_duration scaleX:1/_endScaleX scaleY:1/_endScaleY];
}
@end

//
// Blink
//
#pragma mark - CCBlink
@implementation CCActionBlink {
    NSUInteger _times;
    BOOL _originalState;
}

+(instancetype) actionWithDuration: (CCTime) t blinks: (NSUInteger) b
{
	return [[ self alloc] initWithDuration: t blinks: b];
}

-(id) initWithDuration: (CCTime) t blinks: (NSUInteger) b
{
	if( (self=[super initWithDuration: t] ) )
		_times = b;

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration: [self duration] blinks: _times];
	return copy;
}

-(void) startWithTarget:(id)target
{
	[super startWithTarget:target];
	_originalState = [target visible];
}

-(void) update: (CCTime) t
{
	if( ! [self isDone] ) {
		CCTime slice = 1.0f / _times;
		CCTime m = fmodf(t, slice);
		[_target setVisible: (m > slice/2) ? YES : NO];
	}
}

-(void) stop
{
	[_target setVisible:_originalState];
	[super stop];
}

-(CCActionInterval*) reverse
{
	// return 'self'
	return [[self class] actionWithDuration:_duration blinks: _times];
}
@end

//
// FadeIn
//
#pragma mark - CCFadeIn
@implementation CCActionFadeIn
-(void) update: (CCTime) t
{
	[(Node*) _target setOpacity: 1.0 *t];
}

-(CCActionInterval*) reverse
{
	return [CCActionFadeOut actionWithDuration:_duration];
}
@end

//
// FadeOut
//
#pragma mark - CCFadeOut
@implementation CCActionFadeOut
-(void) update: (CCTime) t
{
	[(Node*) _target setOpacity: 1.0 *(1-t)];
}

-(CCActionInterval*) reverse
{
	return [CCActionFadeIn actionWithDuration:_duration];
}
@end

//
// FadeTo
//
#pragma mark - CCFadeTo
@implementation CCActionFadeTo {
    CGFloat _toOpacity;
    CGFloat _fromOpacity;
}

+(instancetype) actionWithDuration: (CCTime) t opacity: (CGFloat) o
{
	return [[ self alloc] initWithDuration: t opacity: o];
}

-(id) initWithDuration: (CCTime) t opacity: (CGFloat) o
{
	if( (self=[super initWithDuration: t] ) )
		_toOpacity = o;

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	CCAction *copy = [[[self class] allocWithZone: zone] initWithDuration:[self duration] opacity:_toOpacity];
	return copy;
}

-(void) startWithTarget:(Node *)aTarget
{
	[super startWithTarget:aTarget];
	_fromOpacity = [(Node*)_target opacity];
}

-(void) update: (CCTime) t
{
	[(Node*)_target setOpacity:_fromOpacity + ( _toOpacity - _fromOpacity ) * t];
}
@end

//
// DelayTime
//
#pragma mark - CCDelayTime
@implementation CCActionDelay
-(void) update: (CCTime) t
{
	return;
}

-(id)reverse
{
	return [[self class] actionWithDuration:_duration];
}
@end

//
// ReverseTime
//
#pragma mark - CCReverseTime
@implementation CCActionReverse {
    CCActionFiniteTime * _other;
}

+(instancetype) actionWithAction: (CCActionFiniteTime*) action
{
	// casting to prevent warnings
	CCActionReverse *a = [self alloc];
	return [a initWithAction:action];
}

-(id) initWithAction: (CCActionFiniteTime*) action
{
	NSAssert(action != nil, @"CCReverseTime: action should not be nil");
	NSAssert(action != _other, @"CCReverseTime: re-init doesn't support using the same arguments");

	if( (self=[super initWithDuration: [action duration]]) ) {
		// Don't leak if action is reused
		_other = action;
	}

	return self;
}

-(id) copyWithZone: (NSZone*) zone
{
	return [[[self class] allocWithZone: zone] initWithAction:[_other copy] ];
}


-(void) startWithTarget:(id)aTarget
{
	[super startWithTarget:aTarget];
	[_other startWithTarget:_target];
}

-(void) stop
{
	[_other stop];
	[super stop];
}

-(void) update:(CCTime)t
{
	[_other update:1-t];
}

-(CCActionInterval*) reverse
{
	return [_other copy];
}
@end
/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2020-present quiprr
 * Modified work Copyright (c) 2021 ProcursusTeam
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
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import "NSData+HexString.h"
#include "defaults.h"

/*
 * write <domain> <domain_rep>   writes domain (overwrites existing)
 * write <domain> <key> <value>  writes key for domain
 *
 * <value> is one of:
 *   <value_rep>
 *   -string <string_value>
 *   -data <hex_digits>
 *   -int[eger] <integer_value>
 *   -float  <floating-point_value>
 *   -bool[ean] (true | false | yes | no)
 *   -date <date_rep>
 *   -array <value1> <value2> ...
 *   -array-add <value1> <value2> ...
 *   -dict <key1> <value1> <key2> <value2> ...
 *   -dict-add <key1> <value1> ...
 */

int defaultsWrite(NSArray *args, NSString *ident, CFStringRef host, CFStringRef container) {
	if (args.count == 4) {
		NSObject* rep = parsePropertyList([args objectAtIndex:3]);

		if (![rep isKindOfClass:[NSDictionary class]]) {
			NSLog(@"\nRep argument is not a dictionary\nDefaults have not been changed.\n");
			return 1;
		}

		NSMutableArray *toRemove;

		NSArray *keys = (__bridge_transfer NSArray*)CFPreferencesCopyKeyList(
				(__bridge CFStringRef)ident,
				kCFPreferencesCurrentUser, host);
		if (keys.count == 0) {
			toRemove = NULL;
		} else {
			toRemove = [keys mutableCopy];
			[toRemove removeObjectsInArray:[(NSDictionary *)rep allKeys]];
		}

		for (NSString *key in [(NSDictionary *)rep allKeys]) {
			CFPreferencesSetValue((__bridge CFStringRef)key,
					(__bridge CFPropertyListRef)[(NSDictionary*)rep objectForKey:key],
					(__bridge CFStringRef)ident, kCFPreferencesCurrentUser, host);
		}
		for (NSString *key in toRemove) {
			CFPreferencesSetValue((__bridge CFStringRef)key, NULL,
					(__bridge CFStringRef)ident, kCFPreferencesCurrentUser, host);
		}
		CFPreferencesSynchronize((__bridge CFStringRef)ident, kCFPreferencesCurrentUser,
				host);
		return 0;
	}

	if (args.count == 5) {
		NSObject *rep;
		// Should probably clean this up
		if (isType([args objectAtIndex:4])) {
			usage();
			return 255;
		} else if ([[args objectAtIndex:4] isEqualToString:@"-array"]) {
			rep = [[NSArray alloc] init];
		} else if ([[args objectAtIndex:4] isEqualToString:@"-dict"]) {
			rep = [[NSDictionary alloc] init];
		} else if ([[args objectAtIndex:4] isEqualToString:@"-array-add"] || [[args objectAtIndex:4] isEqualToString:@"-dict-add"]) {
			rep = nil;
		} else {
			rep = parsePropertyList([args objectAtIndex:4]);
		}
		if (rep != nil) {
			CFPreferencesSetValue((__bridge CFStringRef)[args objectAtIndex:3], (__bridge CFPropertyListRef)rep,
				(__bridge CFStringRef)ident, kCFPreferencesCurrentUser, host);
			Boolean ret = CFPreferencesSynchronize((__bridge CFStringRef)ident,
					kCFPreferencesCurrentUser, host);
			if (!ret) {
				NSLog(@"Could not write domain %@; exiting", prettyName(ident));
				return 1;
			}
		}
		return 0;
	} else if (args.count >= 6) {
		CFPropertyListRef value = NULL;
		NSMutableArray *array = [[NSMutableArray alloc] init];
		NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
		if ([[args objectAtIndex:4] isEqualToString: @"-array"] || [[args objectAtIndex:4] isEqualToString: @"-array-add"]) { // Array
			if ([[args objectAtIndex:4] isEqualToString: @"-array-add"]) {
				CFPropertyListRef prepend = CFPreferencesCopyValue((__bridge CFStringRef)[args objectAtIndex:3],
					(__bridge CFStringRef)ident, kCFPreferencesCurrentUser, host);
				if (prepend != NULL) {
					if (CFGetTypeID(prepend) != CFArrayGetTypeID()) {
						NSLog(@"Value for key %@ is not an array; cannot append.  Leaving defaults unchanged.\n", [args objectAtIndex:3]);
						return 1;
					}
					[array addObjectsFromArray:(__bridge_transfer NSArray*)prepend];
				}
			}
			NSArray *arrayItems = [args subarrayWithRange:NSMakeRange(5, args.count - 5)];
			for (int i = 0; i < arrayItems.count; i++) {
				if ([[arrayItems objectAtIndex:i] isEqualToString:@"-array"] || [[arrayItems objectAtIndex:i] isEqualToString:@"-dict"]) {
					NSLog(@"Cannot nest composite types (arrays and dictionaries); exiting");
					return 1;
				}
				if (isType([arrayItems objectAtIndex:i])) {
					if (i >= arrayItems.count - 1) {
						usage();
						return 255;
					}
					[array addObject: (__bridge NSObject*)parseTypedArg([arrayItems objectAtIndex:i], [arrayItems objectAtIndex:++i], true)];
				} else {
					[array addObject: (__bridge NSObject*)parseTypedArg(NULL, [arrayItems objectAtIndex:i], true)];
				}
			}
			value = (__bridge CFPropertyListRef)array;
		} else if ([[args objectAtIndex:4] isEqualToString: @"-dict"] || [[args objectAtIndex:4] isEqualToString: @"-dict-add"]) { // Dictionary
			if ([[args objectAtIndex:4] isEqualToString: @"-dict-add"]) {
				CFPropertyListRef prepend = CFPreferencesCopyValue((__bridge CFStringRef)[args objectAtIndex:3],
					(__bridge CFStringRef)ident, kCFPreferencesCurrentUser, host);
				if (prepend != NULL) {
					if (CFGetTypeID(prepend) != CFDictionaryGetTypeID()) {
						NSLog(@"Value for key %@ is not a dictionary; cannot append.  Leaving defaults unchanged.\n", [args objectAtIndex:3]);
						return 1;
					}
					[dict addEntriesFromDictionary:(__bridge_transfer NSDictionary*)prepend];
				}
			}
			NSArray *arrayItems = [args subarrayWithRange:NSMakeRange(5, args.count - 5)];
			for (int i = 0; i < arrayItems.count; i++) {
				if ([[arrayItems objectAtIndex:i] isEqualToString:@"-array"] || [[arrayItems objectAtIndex:i] isEqualToString:@"-dict"]) {
					NSLog(@"Cannot nest composite types (arrays and dictionaries); exiting\n");
					return 1;
				}
				if (isType([arrayItems objectAtIndex:i])) {
					if ([[arrayItems objectAtIndex:i] isEqualToString:@"-string"]) {
						i++;
					} else {
						if (arrayItems.count == 1) {
							usage();
							return 255;
						} else
							NSLog(@"Dictionary keys must be strings\n");
						return 1;
					}
				}
				if (i == arrayItems.count - 1) {
					NSLog(@"Key %@ lacks a corresponding value\n", [arrayItems objectAtIndex:i]);
					return 1;
				}
				if (isType([arrayItems objectAtIndex:i + 1])) {
					if (i >= arrayItems.count - 2) {
						usage();
						return 255;
					}
					[dict setObject:(__bridge_transfer NSObject*)parseTypedArg([arrayItems objectAtIndex:i + 1], [arrayItems objectAtIndex:i + 2], true)
						forKey:[arrayItems objectAtIndex:i]];
					i += 2;
				} else {
					[dict setObject:(__bridge_transfer NSObject*)parseTypedArg(NULL, [arrayItems objectAtIndex:i + 1], true)
						forKey:[arrayItems objectAtIndex:i]];
					i++;
				}
			}
			value = (__bridge CFPropertyListRef)dict;
		} else {
			value = parseTypedArg([args objectAtIndex:4], [args objectAtIndex:5], false);

			if (isType([args objectAtIndex:4]) && args.count >= 7) {
				NSLog(@"Unexpected argument %@; leaving defaults unchanged.\n", [args objectAtIndex:6]);
				return 1;
			} else if (!isType([args objectAtIndex:4]) && args.count >= 6) {
				NSLog(@"Unexpected argument %@; leaving defaults unchanged.\n", [args objectAtIndex:5]);
				return 1;
			}
		}

		CFPreferencesSetValue((__bridge CFStringRef)[args objectAtIndex:3], value,
			(__bridge CFStringRef)ident, kCFPreferencesCurrentUser, host);
		CFPreferencesSynchronize((__bridge CFStringRef)ident, kCFPreferencesCurrentUser, host);
		return 0;
	}

	return 1;
}

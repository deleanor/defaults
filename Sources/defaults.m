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

const unsigned char defaultsVersionString[] = "@(#)PROGRAM:defaults  PROJECT:defaults-1.0.1\n";

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

#include "defaults.h"

int main(int argc, char *argv[], char *envp[])
{
	@autoreleasepool {
		NSMutableArray *args = [[[NSProcessInfo processInfo] arguments] mutableCopy];

		CFStringRef host = kCFPreferencesAnyHost;
		if (args.count >= 2 && [[args objectAtIndex:1] isEqualToString:@"-currentHost"]) {
			host = kCFPreferencesCurrentHost;
			[args removeObjectAtIndex:1];
		} else if (args.count >= 3  && [[args objectAtIndex:1] isEqualToString:@"-host"]) {
			host = (__bridge CFStringRef)[args objectAtIndex:2];
			[args removeObjectAtIndex:2];
			[args removeObjectAtIndex:1];
		}

		if (args.count == 1) {
			usage();
			return 255;
		}

		CFStringRef container = CFSTR("kCFPreferencesNoContainer");

		[args replaceObjectAtIndex:1 withObject:[[args objectAtIndex:1] lowercaseString]];

		if (args.count == 1 || (args.count >= 2 && [[args objectAtIndex:1] isEqualToString:@"help"])) {
			usage();
			return args.count == 1 ? 255 : 0;
		}

		if ([[args objectAtIndex:1] isEqualToString:@"domains"]) {
			NSMutableArray *domains = [(__bridge_transfer NSArray*)CFPreferencesCopyApplicationList(kCFPreferencesCurrentUser, host) mutableCopy];
			if (domains.count != 0) {
				[domains removeObjectAtIndex:[domains indexOfObject:(id)kCFPreferencesAnyApplication]];
				[domains sortUsingSelector:@selector(compare:)];
			}
			printf("%s\n", [domains componentsJoinedByString:@", "].UTF8String);
			return 0;
		} else if (args.count == 2 && [[args objectAtIndex:1] isEqualToString:@"read"]) {
			NSArray *prefs = (__bridge_transfer NSArray *)
				CFPreferencesCopyApplicationList(kCFPreferencesCurrentUser, host);
			NSMutableDictionary *out = [NSMutableDictionary new];
			for (NSString *domain in prefs) {
				[out setObject:(__bridge_transfer NSDictionary*)CFPreferencesCopyMultiple(NULL, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, host)
								forKey:prettyName(domain)];
			}
			NSString *outputString = (NSString*)[NSString stringWithFormat:@"%@", out];
			printf("%s\n", [outputString cString]);
			return 0;
		}

		if (args.count >= 3 && [[args objectAtIndex:1] isEqualToString:@"find"]) {
			NSArray *domains = (__bridge_transfer NSArray*)CFPreferencesCopyApplicationList(
					kCFPreferencesCurrentUser, host);
			long found = 0;
			BOOL success = false;
			for (NSString *domain in domains) {
				found = 0;
				if ([domain rangeOfString:[args objectAtIndex:2] options:NSCaseInsensitiveSearch].location != NSNotFound)
					found++;
				NSDictionary *dict = (__bridge_transfer NSDictionary*)CFPreferencesCopyMultiple(NULL,
						(__bridge CFStringRef)domain, kCFPreferencesCurrentUser, host);
				NSArray *flattened = flatten(dict);
				NSLog(@"%@", flattened);
				for (NSString *item in flattened) {
					if ([item rangeOfString:[args objectAtIndex:2] options:NSCaseInsensitiveSearch].location != NSNotFound)
						found++;
				}
				if (found) {
					success = true;
					printf("Found %ld keys in domain '%s': %s\n", found,
							prettyName(domain).UTF8String, dict.description.UTF8String);
				}
			}
			if (!success)
				NSLog(@"No domain, key, nor value containing '%@'", [args objectAtIndex:2]);
			return 0;
		}

		NSString *appid;

		if (args.count >= 3) {
			if ([[args objectAtIndex:2] isEqualToString:@"-g"] || [[args objectAtIndex:2] isEqualToString:@"-globalDomain"] ||
					[[args objectAtIndex:2] isEqualToString:@"NSGlobalDomain"] || [[args objectAtIndex:2] isEqualToString:@"Apple Global Domain"])
				appid = (__bridge NSString*)kCFPreferencesAnyApplication;
			else if (args.count >= 4 && [[args objectAtIndex:2] isEqualToString:@"-app"]) {
				BOOL directory;
				if ([[NSFileManager defaultManager] fileExistsAtPath:[args objectAtIndex:3] isDirectory:&directory] && directory) {
					NSBundle *appBundle = [NSBundle bundleWithPath:[[args objectAtIndex:3] stringByResolvingSymlinksInPath]];
					if (appBundle == nil) {
						NSLog(@"Couldn't open application %@; defaults unchanged", [args objectAtIndex:3]);
						return 1;
					}
					appid = [appBundle bundleIdentifier];
					if (appid == nil) {
						NSLog(@"Can't determine domain name for application %@; defaults unchanged", [args objectAtIndex:3]);
						return 1;
					}
				} /*else {
					LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
					NSArray *apps = [workspace allInstalledApplications];
					for (LSApplicationProxy *proxy in apps) {
						if ([[args objectAtIndex:3] isEqualToString:[proxy localizedNameForContext:nil]]) {
							appid = proxy.applicationIdentifier;
							break;
						}
					}
					if (appid == nil) {
						NSLog(@"Couldn't find an application named \"%@\"; defaults unchanged", [args objectAtIndex:3]);
						return 1;
					}
				}*/
				[args removeObjectAtIndex:2];
			} else if ([[args objectAtIndex:2] hasPrefix:@"/"]) {
				appid = [[args objectAtIndex:2] stringByResolvingSymlinksInPath];
			} else
				appid = [args objectAtIndex:2];
		}

		if ([[args objectAtIndex:1] isEqualToString:@"read"]) {
			NSDictionary *result = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(NULL,
					(__bridge CFStringRef)appid, kCFPreferencesCurrentUser, host);

			if (args.count == 3) {
				if ([result count] == 0) {
					NSLog(@"\nDomain %@ does not exist\n", appid);
					return 1;
				}
				printf("%s\n", result.description.UTF8String);
				return 0;
			} else {
				if ([result objectForKey:[args objectAtIndex:3]] == nil) {
					NSLog(@"\nThe domain/default pair of (%@, %@) does not exist\n", appid, [args objectAtIndex:3]);
					return 1;
				}
				printf("%s\n", [[result objectForKey:[args objectAtIndex:3]] description].UTF8String);
				return 0;
			}
		}

		if (args.count == 5 && [[args objectAtIndex:1] isEqualToString:@"rename"]) {
			CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)[args objectAtIndex:3],
					(__bridge CFStringRef)appid, kCFPreferencesCurrentUser, host);
			if (value == NULL) {
				NSLog(@"Key %@ does not exist in domain %@; leaving defaults unchanged", [args objectAtIndex:3], prettyName(appid));
				return 1;
			}
			CFPreferencesSetValue((__bridge CFStringRef)[args objectAtIndex:4], value, (__bridge CFStringRef)appid,
					kCFPreferencesCurrentUser, host);
			CFPreferencesSetValue((__bridge CFStringRef)[args objectAtIndex:3], NULL, (__bridge CFStringRef)appid,
					kCFPreferencesCurrentUser, host);
			Boolean ret = CFPreferencesSynchronize((__bridge CFStringRef)appid,
						kCFPreferencesCurrentUser, host);
			if (!ret) {
				NSLog(@"Failed to write domain %@", prettyName(appid));
				return 1;
			}
			return 0;
		}

		if (args.count >= 4 && [[args objectAtIndex:1] isEqualToString:@"read-type"]) {
			CFPropertyListRef result = CFPreferencesCopyValue((__bridge CFStringRef)[args objectAtIndex:3],
					(__bridge CFStringRef)appid, kCFPreferencesCurrentUser, host);
			if (result == NULL) {
				NSLog(@"\nThe domain/default pair of (%@, %@) does not exist\n", appid, [args objectAtIndex:3]);
				return 1;
			}
			/*
			CFTypeID type = CFGetTypeID(result);
			if (type == CFStringGetTypeID()) {
				printf("Type is string\n");
			} else if (type == CFDataGetTypeID()) {
				printf("Type is data\n");
			} else if (type == CFNumberGetTypeID()) {
				if (CFNumberIsFloatType(result))
					printf("Type is float\n");
				else
					printf("Type is integer\n");
			} else if (type == CFBooleanGetTypeID()) {
				printf("Type is boolean\n");
			} else if (type == CFDateGetTypeID()) {
				printf("Type is date\n");
			} else if (type == CFArrayGetTypeID()) {
				printf("Type is array\n");
			} else if (type == CFDictionaryGetTypeID()) {
				printf("Type is dictionary\n");
			} else {
				printf("Found a value that is not of a known property list type\n");
			}
			*/
			CFRelease(result);
			return 0;
		}

		if ([[args objectAtIndex:1] isEqualToString:@"export"]) {
			if (args.count < 3) {
				usage();
				return 255;
			}
			if (args.count < 4) {
				NSLog(@"\nNeed a path to write to");
				return 1;
			}
			NSArray *keys = (__bridge_transfer NSArray*)CFPreferencesCopyKeyList((__bridge CFStringRef)appid,
					kCFPreferencesCurrentUser, host);
			NSDictionary *out = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(
					(__bridge CFArrayRef)keys, (__bridge CFStringRef)appid,
					kCFPreferencesCurrentUser, host);
			if (out == 0) {
				NSLog(@"\nThe domain %@ does not exist\n", appid);
				return 1;
			}
			NSString *errorDescription;
			NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
			if ([[args objectAtIndex:3] isEqualToString:@"-"]) {
				format = NSPropertyListXMLFormat_v1_0;
			}

			NSData *outData = [NSPropertyListSerialization dataFromPropertyList:out
				format:format
				errorDescription:&errorDescription];

			if (errorDescription) {
				NSLog(@"Could not export domain %@ to %@ due to %@", appid, [args objectAtIndex:3], errorDescription);
				return 1;
			}
			if (format == NSPropertyListXMLFormat_v1_0) {
				NSFileHandle *fh = [NSFileHandle fileHandleWithStandardOutput];
				[fh writeData:outData];
			} else
				[outData writeToFile:[args objectAtIndex:3] atomically:true];
			return 0;
		}

		if ([[args objectAtIndex:1] isEqualToString:@"import"]) {
			if (args.count < 3) {
				usage();
				return 255;
			}
			if (args.count < 4) {
				NSLog(@"\nNeed a path to read from");
				return 1;
			}

			NSData *inputData;
			if ([[args objectAtIndex:3] isEqualToString:@"-"]) {
				NSFileHandle *fh = [NSFileHandle fileHandleWithStandardInput];
				inputData = [fh readDataToEndOfFile];
			} else {
				inputData = [NSData dataWithContentsOfFile:[args objectAtIndex:3]];
			}
			if (inputData == nil) {
				NSLog(@"Could not read data from %@", [args objectAtIndex:3]);
				return 1;
			}

			NSString *errorDescription;
			NSObject *inputDict = [NSPropertyListSerialization propertyListFromData:inputData
			mutabilityOption:NSPropertyListImmutable
			 format:0
			errorDescription:&errorDescription];
			if (errorDescription) {
				NSLog(@"Could not parse property list from %@ due to %@", [args objectAtIndex:3], errorDescription);
				return 1;
			}

			if (![inputDict isKindOfClass:[NSDictionary class]]) {
				NSLog(@"Property list %@ was not a dictionary\nDefaults have not been changed.\n", inputDict);
				return 1;
			}
			for (NSString *key in [(NSDictionary*)inputDict allKeys]) {
				CFPreferencesSetValue((__bridge CFStringRef)key,
						(__bridge CFPropertyListRef)[(NSDictionary*)inputDict objectForKey:key],
						(__bridge CFStringRef)appid, kCFPreferencesCurrentUser, host);
			}
			CFPreferencesSynchronize((__bridge CFStringRef)appid, kCFPreferencesCurrentUser,
					host);
			return 0;
		}

		if ((args.count == 4 || args.count == 3) && ([[args objectAtIndex:1] isEqualToString:@"delete"] ||
				/* remove is an undocumented alias for delete */ [[args objectAtIndex:1] isEqualToString:@"remove"])) {
			if (args.count == 4) {
				CFPropertyListRef result = CFPreferencesCopyValue((__bridge CFStringRef)[args objectAtIndex:3],
						(__bridge CFStringRef)appid, kCFPreferencesCurrentUser, host);
				if (result == NULL) {
					NSLog(@"\nDomain (%@) not found.\nDefaults have not been changed.\n", appid);
					CFRelease(result);
					return 1;
				}
				CFPreferencesSetValue((__bridge CFStringRef)[args objectAtIndex:3], NULL, (__bridge CFStringRef)appid,
						kCFPreferencesCurrentUser, host);
				Boolean ret = CFPreferencesSynchronize((__bridge CFStringRef)appid,
						kCFPreferencesCurrentUser, host);
				return ret ? 0 : 1;
			} else if (args.count == 3) {
				CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)appid,
						kCFPreferencesCurrentUser, host);
				if (keys == NULL) {
					NSLog(@"\nDomain (%@) not found.\nDefaults have not been changed.\n", appid);
					return 1;
				}
				for (NSString *key in (__bridge NSArray*)keys) {
					CFPreferencesSetValue((__bridge CFStringRef)key, NULL,
							(__bridge CFStringRef)appid, kCFPreferencesCurrentUser, host);
				}
				Boolean ret = CFPreferencesSynchronize((__bridge CFStringRef)appid,
						kCFPreferencesCurrentUser, host);
				return ret ? 0 : 1;
			}
			return 1;
		}

		if ([[args objectAtIndex:1] isEqualToString:@"write"]) {
			if (args.count < 4) {
				usage();
				return 255;
			} else {
				return defaultsWrite(args, appid, host, container);
			}
		}

		usage();
		return 255;
	}
}

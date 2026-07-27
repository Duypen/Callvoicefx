#import "CVFMusicPickerController.h"

#define kMusicFolder @"/var/mobile/Media/CallVoiceFX"
#define kPrefsPath @"/var/mobile/Library/Preferences/com.yourname.callvoicefx.plist"

@implementation CVFMusicPickerController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *err;
        NSArray *files = [fm contentsOfDirectoryAtPath:kMusicFolder error:&err];
        if (err || files.count == 0) {
            PSSpecifier *empty = [PSSpecifier preferenceSpecifierNamed:@"Chưa có file nhạc nào"
                                                                 target:self
                                                                    set:nil
                                                                    get:nil
                                                                 detail:nil
                                                                   cell:PSStaticTextCell
                                                                   edit:nil];
            [specs addObject:empty];
        } else {
            for (NSString *file in files) {
                NSString *ext = file.pathExtension.lowercaseString;
                if (![ext isEqualToString:@"mp3"] && ![ext isEqualToString:@"m4a"] && ![ext isEqualToString:@"wav"]) {
                    continue;
                }
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:file
                                                                    target:self
                                                                       set:@selector(setMusicFile:specifier:)
                                                                       get:nil
                                                                    detail:nil
                                                                      cell:PSLinkListCell
                                                                      edit:nil];
                [specs addObject:spec];
            }
        }
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)setMusicFile:(id)value specifier:(PSSpecifier *)specifier {
    NSString *chosenFile = specifier.name;
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: [NSMutableDictionary dictionary];
    prefs[@"CVFMusicFile"] = chosenFile;
    [prefs writeToFile:kPrefsPath atomically:YES];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          CFSTR("com.yourname.callvoicefx/reload"),
                                          NULL, NULL, YES);

    [self.navigationController popViewControllerAnimated:YES];
}

@end

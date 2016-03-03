
#import <Cocoa/Cocoa.h>

int main(int argc, char *argv[]) {
  id pool = [NSAutoreleasePool new];

  NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/irccloud.log"];
  freopen([logPath fileSystemRepresentation], "w", stderr);

  [pool release];

  return NSApplicationMain(argc,  (const char **) argv);
}

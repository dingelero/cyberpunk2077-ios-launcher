#import <Foundation/Foundation.h>
#include <mach-o/loader.h>
// Read-only parameter snapshot for the exact audited guest image.
NSDictionary *CPGameEnginePatchAudit(const struct mach_header_64 *header);

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

typedef void (*CPHostLogger)(NSString *key, id value);
void CPHostDiagnosticsInitialize(NSDictionary *initial);
void CPHostRecordEvent(NSString *key, id value);
void CPHostReportFailure(NSString *stage, NSString *message);
NSDictionary *CPHostDiagnosticSnapshot(void);
typedef NSDictionary *(*CPNativeMetalReportGetter)(void);
void CPHostStartMemoryTrace(id<MTLDevice> device, CPNativeMetalReportGetter metalReport);
void CPHostStartPerformanceTrace(id<MTLDevice> device, CPNativeMetalReportGetter metalReport, BOOL detailed);

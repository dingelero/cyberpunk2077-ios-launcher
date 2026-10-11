// Cyberpunk compatibility for Security APIs unavailable on iOS.
// ABI checked against Xcode 27 macOS SDK SecCertificate/SecIdentity/SecImportExport.
// Certificate/key objects and trust decisions come from Apple's native Security.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <stddef.h>
#include <stdint.h>

// Native macOS enum/structure ABI; no desktop Security header is compiled into iOS.
enum { CPFormatUnknown=0, CPFormatOpenSSL=1, CPFormatRawKey=4,
       CPFormatX509=9, CPFormatPEMSequence=10, CPFormatPKCS7=11, CPFormatPKCS12=12 };
enum { CPTypeUnknown=0, CPTypePrivateKey=1, CPTypePublicKey=2,
       CPTypeSessionKey=3, CPTypeCertificate=4, CPTypeAggregate=5 };
typedef struct {
    uint32_t version,flags;
    CFTypeRef passphrase;
    CFStringRef alertTitle,alertPrompt;
    CFTypeRef accessRef;
    CFArrayRef keyUsage,keyAttributes;
} CPSecItemKeyParameters;
_Static_assert(sizeof(CPSecItemKeyParameters)==56,"macOS arm64 key parameter ABI");
_Static_assert(offsetof(CPSecItemKeyParameters,passphrase)==8,"macOS arm64 passphrase offset");

static NSMutableArray *ImportedIdentities(void) {
    static NSMutableArray *items;static dispatch_once_t once;
    dispatch_once(&once,^{items=[NSMutableArray new];});return items;
}
static void SetError(CFErrorRef *error,OSStatus status) {
    if(error)*error=CFErrorCreate(kCFAllocatorDefault,kCFErrorDomainOSStatus,status,NULL);
}
CFStringRef SecCertificateCopyLongDescription(CFAllocatorRef allocator,SecCertificateRef certificate,CFErrorRef *error) {
    if(error)*error=NULL;
    if(!certificate || CFGetTypeID(certificate)!=SecCertificateGetTypeID()){SetError(error,errSecParam);return NULL;}
    CFStringRef subject=SecCertificateCopySubjectSummary(certificate);
    if(!subject){SetError(error,errSecDecode);return NULL;}
    CFDataRef data=SecCertificateCopyData(certificate);
    CFStringRef result=CFStringCreateWithFormat(allocator,NULL,CFSTR("%@ (X.509 certificate, %ld DER bytes)"),subject,data?(long)CFDataGetLength(data):0L);
    CFRelease(subject);if(data)CFRelease(data);
    if(!result)SetError(error,errSecAllocate);
    return result; // Copy API returns a retained real certificate description.
}
static BOOL CertificateEquals(SecCertificateRef left,SecCertificateRef right) {
    CFDataRef a=SecCertificateCopyData(left),b=SecCertificateCopyData(right);
    BOOL same=a&&b&&CFEqual(a,b);if(a)CFRelease(a);if(b)CFRelease(b);return same;
}
OSStatus SecIdentityCreateWithCertificate(CFTypeRef keychainOrArray,SecCertificateRef certificate,SecIdentityRef *identity) {
    if(identity)*identity=NULL;
    if(!identity || !certificate || CFGetTypeID(certificate)!=SecCertificateGetTypeID())return errSecParam;
    if(keychainOrArray){NSLog(@"CP_SECURITY desktop_keychain_search_unavailable");return errSecUnimplemented;}
    NSMutableArray *candidates=[NSMutableArray new];
    @synchronized(ImportedIdentities()){[candidates addObjectsFromArray:ImportedIdentities()];}
    NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassIdentity,
                          (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll,
                          (__bridge id)kSecReturnRef:@YES};
    CFTypeRef found=NULL;OSStatus search=SecItemCopyMatching((__bridge CFDictionaryRef)query,&found);
    if(search==errSecSuccess && found){
        if(CFGetTypeID(found)==CFArrayGetTypeID())[candidates addObjectsFromArray:(__bridge NSArray *)found];
        else[candidates addObject:(__bridge id)found];
    }
    for(id item in candidates) {
        CFTypeRef value=(__bridge CFTypeRef)item;if(CFGetTypeID(value)!=SecIdentityGetTypeID())continue;
        SecCertificateRef matched=NULL;OSStatus status=SecIdentityCopyCertificate((SecIdentityRef)value,&matched);
        BOOL same=status==errSecSuccess && matched && CertificateEquals(certificate,matched);
        if(matched)CFRelease(matched);
        if(same){*identity=(SecIdentityRef)CFRetain(value);if(found)CFRelease(found);return errSecSuccess;}
    }
    if(found)CFRelease(found);
    return search!=errSecSuccess && search!=errSecItemNotFound?search:errSecItemNotFound;
}
static NSData *PEMData(SecCertificateRef certificate) {
    CFDataRef bytes=SecCertificateCopyData(certificate);if(!bytes)return nil;
    NSString *base64=[(__bridge NSData *)bytes base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength|NSDataBase64EncodingEndLineWithLineFeed];
    NSData *result=[[NSString stringWithFormat:@"-----BEGIN CERTIFICATE-----\n%@\n-----END CERTIFICATE-----\n",base64] dataUsingEncoding:NSASCIIStringEncoding];
    CFRelease(bytes);return result;
}
OSStatus SecItemExport(CFTypeRef itemOrArray,uint32_t format,uint32_t flags,const CPSecItemKeyParameters *parameters,CFDataRef *exportedData) {
    if(exportedData)*exportedData=NULL;
    if(!exportedData || !itemOrArray || flags&~1U)return errSecParam;
    if(parameters && parameters->version!=0)return errSecParam;
    NSArray *items=CFGetTypeID(itemOrArray)==CFArrayGetTypeID()?(__bridge NSArray *)itemOrArray:@[(__bridge id)itemOrArray];
    if(!items.count)return errSecParam;
    BOOL pem=format==CPFormatPEMSequence || (flags&1U) || (format==CPFormatUnknown && items.count>1);
    if(format!=CPFormatUnknown && format!=CPFormatX509 && format!=CPFormatPEMSequence){NSLog(@"CP_SECURITY export_format_unavailable %u",format);return errSecUnimplemented;}
    if(!pem && items.count!=1)return errSecUnimplemented;
    NSMutableData *output=[NSMutableData new];
    for(id item in items) {
        CFTypeRef value=(__bridge CFTypeRef)item;
        if(CFGetTypeID(value)!=SecCertificateGetTypeID()){NSLog(@"CP_SECURITY non_certificate_export_unavailable");return errSecUnimplemented;}
        SecCertificateRef certificate=(SecCertificateRef)value;
        if(pem){NSData *part=PEMData(certificate);if(!part)return errSecDecode;[output appendData:part];}
        else{CFDataRef data=SecCertificateCopyData(certificate);if(!data)return errSecDecode;[output appendData:(__bridge NSData *)data];CFRelease(data);}
    }
    *exportedData=CFBridgingRetain(output);return errSecSuccess;
}
static OSStatus ImportCertificateBytes(NSData *data,NSMutableArray *items) {
    SecCertificateRef cert=SecCertificateCreateWithData(kCFAllocatorDefault,(__bridge CFDataRef)data);
    if(!cert)return errSecDecode;[items addObject:(__bridge id)cert];CFRelease(cert);return errSecSuccess;
}
OSStatus SecItemImport(CFDataRef importedData,CFStringRef fileNameOrExtension,uint32_t *format,uint32_t *itemType,uint32_t flags,
                       const CPSecItemKeyParameters *parameters,CFTypeRef importKeychain,CFArrayRef *outItems) {
    if(outItems)*outItems=NULL;
    if(!importedData || CFGetTypeID(importedData)!=CFDataGetTypeID())return errSecParam;
    if(parameters && parameters->version!=0)return errSecParam;
    if(importKeychain){NSLog(@"CP_SECURITY desktop_keychain_import_unavailable");return errSecUnimplemented;}
    if(parameters && (parameters->flags&2U)){NSLog(@"CP_SECURITY secure_passphrase_prompt_unavailable");return errSecInteractionNotAllowed;}
    if(parameters && (parameters->accessRef || parameters->keyUsage || parameters->keyAttributes)) {
        NSLog(@"CP_SECURITY desktop_key_import_attributes_unavailable");return errSecUnimplemented;
    }
    uint32_t requested=format?*format:CPFormatUnknown;
    if(itemType && *itemType!=CPTypeUnknown && *itemType!=CPTypeCertificate && *itemType!=CPTypeAggregate)return errSecUnimplemented;
    NSData *data=(__bridge NSData *)importedData;NSMutableArray *items=[NSMutableArray new];
    NSString *ascii=[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    uint32_t actual=CPFormatX509,type=CPTypeCertificate;OSStatus status=errSecDecode;
    if(requested==CPFormatUnknown || requested==CPFormatX509 || requested==CPFormatPEMSequence) {
        if([ascii containsString:@"-----BEGIN CERTIFICATE-----"]) {
            NSScanner *scanner=[NSScanner scannerWithString:ascii];NSString *base64;
            while(!scanner.isAtEnd) {
                [scanner scanUpToString:@"-----BEGIN CERTIFICATE-----" intoString:NULL];
                if(![scanner scanString:@"-----BEGIN CERTIFICATE-----" intoString:NULL])break;
                if(![scanner scanUpToString:@"-----END CERTIFICATE-----" intoString:&base64] || ![scanner scanString:@"-----END CERTIFICATE-----" intoString:NULL])return errSecDecode;
                NSData *der=[[NSData alloc] initWithBase64EncodedString:base64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
                if(!der || ImportCertificateBytes(der,items)!=errSecSuccess)return errSecDecode;
            }
            status=items.count?errSecSuccess:errSecDecode;actual=items.count>1?CPFormatPEMSequence:CPFormatX509;type=items.count>1?CPTypeAggregate:CPTypeCertificate;
        } else status=ImportCertificateBytes(data,items);
    }
    NSString *filename=(__bridge NSString *)fileNameOrExtension;
    BOOL pkcs12=requested==CPFormatPKCS12 || [@[@"p12",@"pfx"] containsObject:filename.pathExtension.lowercaseString];
    if(status!=errSecSuccess && pkcs12) {
        CFTypeRef password=parameters?parameters->passphrase:NULL;
        id phrase=@"";
        if(password) {
            if(CFGetTypeID(password)==CFStringGetTypeID())phrase=(__bridge NSString *)password;
            else if(CFGetTypeID(password)==CFDataGetTypeID()){phrase=[[NSString alloc] initWithData:(__bridge NSData *)password encoding:NSUTF8StringEncoding];if(!phrase)return errSecParam;}
            else return errSecParam;
        }
        NSDictionary *options=@{(__bridge id)kSecImportExportPassphrase:phrase,(__bridge id)kSecImportToMemoryOnly:@YES};
        CFArrayRef imported=NULL;status=SecPKCS12Import(importedData,(__bridge CFDictionaryRef)options,&imported);
        if(status!=errSecSuccess){if(imported)CFRelease(imported);return status;}
        for(NSDictionary *entry in (__bridge NSArray *)imported) {
            SecIdentityRef identity=(__bridge SecIdentityRef)entry[(__bridge id)kSecImportItemIdentity];
            if(identity){
                @synchronized(ImportedIdentities()){[ImportedIdentities() addObject:(__bridge id)identity];}
                SecKeyRef key=NULL;if(SecIdentityCopyPrivateKey(identity,&key)==errSecSuccess && key){[items addObject:(__bridge id)key];CFRelease(key);}
            }
            for(id certificate in entry[(__bridge id)kSecImportItemCertChain]?:@[])if(![items containsObject:certificate])[items addObject:certificate];
        }
        if(imported)CFRelease(imported);actual=CPFormatPKCS12;type=CPTypeAggregate;
    } else if(status!=errSecSuccess && requested!=CPFormatUnknown && requested!=CPFormatX509 && requested!=CPFormatPEMSequence)return errSecUnimplemented;
    if(status!=errSecSuccess)return status;
    if(!items.count)return errSecDecode;
    if(format)*format=actual;if(itemType)*itemType=type;if(outItems)*outItems=CFBridgingRetain(items);
    return errSecSuccess;
}

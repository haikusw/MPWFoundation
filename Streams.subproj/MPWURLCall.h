//
//  MPWURLCall.h
//  MPWFoundation
//
//  Created by Marcel Weiher on 02/06/16.
//
//

#import <Foundation/Foundation.h>

@protocol MPWReferencing;
@class MPWRESTOperation<T: id <MPWReferencing>>;

@interface MPWURLCall<T: id <MPWReferencing>> : NSObject

-(id)processed;
-(instancetype)initWithRESTOperation:(MPWRESTOperation<T>*)op;
+(instancetype)callWithRESTOperation:(MPWRESTOperation<T>*)op;

@property (readonly)  MPWRESTOperation  *operation;
@property (nonatomic, strong)  NSURL  *baseURL;
@property (readonly)  T reference;
@property (readonly) NSString *verb;

@property (nonatomic, readonly)  NSURLRequest     *request;
@property (nonatomic, strong)  NSData           *bodyData;
@property (nonatomic, strong)  NSDictionary     *headerDict;

@property (nonatomic, strong)  NSURLResponse    *response;
@property (nonatomic, strong)  NSError          *error;
@property (nonatomic, strong)  NSData           *data;
@property (nonatomic, strong)  id               processedObject;
@property (nonatomic, strong)  NSURLSessionTask *task;
@property (nonatomic, assign)  BOOL             isStreaming;

@property (readonly) NSURL* finalURL;


@end

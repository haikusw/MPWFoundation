//
//  MPWBinaryPListWriter.m
//  MPWFoundation
//
//  Created by Marcel Weiher on 9/14/13.
//
//

#import "MPWBinaryPListWriter.h"
#import "AccessorMacros.h"
#import "MPWIntArray.h"


@interface NSObject(plistWriting)

-(void)writeOnPlist:aPlist;

@end
/*
 From CFBinaryPlist.c
 
 HEADER
 magic number ("bplist")
 file format version
 
 OBJECT TABLE
 variable-sized objects
 
 Object Formats (marker byte followed by additional info in some cases)
 null	0000 0000
 bool	0000 1000			// false
 bool	0000 1001			// true
 fill	0000 1111			// fill byte
 int	0001 nnnn	...		// # of bytes is 2^nnnn, big-endian bytes
 real	0010 nnnn	...		// # of bytes is 2^nnnn, big-endian bytes
 date	0011 0011	...		// 8 byte float follows, big-endian bytes
 data	0100 nnnn	[int]	...	// nnnn is number of bytes unless 1111 then int count follows, followed by bytes
 string	0101 nnnn	[int]	...	// ASCII string, nnnn is # of chars, else 1111 then int count, then bytes
 string	0110 nnnn	[int]	...	// Unicode string, nnnn is # of chars, else 1111 then int count, then big-endian 2-byte uint16_t
 0111 xxxx			// unused
 uid	1000 nnnn	...		// nnnn+1 is # of bytes
 1001 xxxx			// unused
 array	1010 nnnn	[int]	objref*	// nnnn is count, unless '1111', then int count follows
 1011 xxxx			// unused
 set	1100 nnnn	[int]	objref* // nnnn is count, unless '1111', then int count follows
 dict	1101 nnnn	[int]	keyref* objref*	// nnnn is count, unless '1111', then int count follows
 1110 xxxx			// unused
 1111 xxxx			// unused
 
 OFFSET TABLE
 list of ints, byte size of which is given in trailer
 -- these are the byte offsets into the file
 -- number of these is in the trailer
 
 TRAILER
 byte size of offset ints in offset table
 byte size of object refs in arrays and dicts
 number of offsets in offset table (also is number of objects)
 element # in offset table which is top level object
 offset table offset
 
 */


@implementation MPWBinaryPListWriter

objectAccessor(MPWIntArray, offsets, setOffsets)
objectAccessor(NSMutableArray, indexStack, setIndexStack)
objectAccessor(NSMutableArray, reserveIndexes, setResrveIndexes)
scalarAccessor(MPWIntArray*, currentIndexes, setCurrentIndexes)
objectAccessor(NSMapTable, objectTable, setObjectTable)

-(SEL)streamWriterMessage
{
    return @selector(writeOnPlist:);
}

-(id)initWithTarget:(id)aTarget
{

    self=[super initWithTarget:aTarget];
    if (self) {
        inlineOffsetByteSize=4;
    }
    [self setOffsets:[MPWIntArray array]];
    [self setIndexStack:[NSMutableArray array]];
    [self setResrveIndexes:[NSMutableArray array]];
    [self setObjectTable:[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaquePersonality valueOptions:NSPointerFunctionsOpaquePersonality]];
    [self writeHeader];
    
    return self;
}


-(void)setTarget:(id)newVar
{
    [super setTarget:newVar];
    headerWritten=NO;
}

-(MPWIntArray*)newIndexes
{
    MPWIntArray *result=[[reserveIndexes lastObject] retain];
    if ( result ) {
        [result reset];
        [reserveIndexes removeLastObject];
    } else {
        result=[MPWIntArray new];
    }
    return result;
}

-(void)pushIndexStack
{
    currentIndexes=[self newIndexes];
    [indexStack addObject:currentIndexes];
    [currentIndexes release];
}

-(MPWIntArray*)popIndexStack
{
    id lastObject=currentIndexes;
    if ( lastObject) {
        [reserveIndexes addObject:lastObject];
    }
    [indexStack removeLastObject];
    currentIndexes=[indexStack lastObject];
    return lastObject;
}

-(void)addIndex:(int)anIndex
{
    [currentIndexes addInteger:anIndex];
}

-(void)beginArray
{
    [self pushIndexStack];
    //    NSLog(@"currentIndexes after beginArray: %@",currentIndexes);
}

-(void)writeArray:(NSArray*)anArray usingElementBlock:(WriterBlock)aBlock
{
    [self beginArray];
    for ( id o in anArray){
        aBlock(self,o);
    }
    [self endArray];
}

-(void)writeDictionary:(NSDictionary *)dict
{
    [self beginDictionary];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
        [self writeString:key];
        [self writeObject:obj ];
    }];
    [self endDictionary];
}

-(void)writeArray:(NSArray *)anArray
{
    [self writeArray:anArray usingElementBlock:^( MPWBinaryPListWriter *w,id object){
        [w writeObject:object];
    }];
}


-(void)writeDictionaryLikeObject:anObject withContentBlock:(WriterBlock)contentBlock
{
    [self beginDictionary];
    @try {
        contentBlock(self,anObject);
    } @finally {
        [self endDictionary];
    }
}


-(void)beginDictionary
{
    [self pushIndexStack];
}

static inline int integerToBuffer( unsigned char *buffer, long anInt, int numBytes  )
{
    for (int i=numBytes-1;i>=0;i--) {
        buffer[i]=anInt & 0xff;
        anInt>>=8;
    }
    return numBytes;
}

-(void)writeInteger:(long)anInt numBytes:(int)numBytes
{
    unsigned char buffer[16];
    integerToBuffer(buffer, anInt, numBytes);
    TARGET_APPEND(buffer, numBytes);
}

-(void)writeIntArray:(MPWIntArray*)array offset:(int)start skip:(int)stride numBytes:(int)numBytes
{
#define BUFSIZE  8000
    unsigned char buffer[BUFSIZE];
    unsigned char *cur=buffer;
    int maxCount=[array count];
    int *ptrs=[array integers];
    for (int i=start;i<maxCount;i+=stride) {
        //        NSLog(@"write array[%d]=%d",i,[array integerAtIndex:i]);
        cur+=integerToBuffer(cur, ptrs[i], numBytes);
        if ( cur-buffer > BUFSIZ-100) {
            TARGET_APPEND(buffer, cur-buffer);
            cur=buffer;
        }
    }
    TARGET_APPEND(buffer, cur-buffer);
}



-(void)writeIntArray:(MPWIntArray*)array numBytes:(int)numBytes
{
    [self writeIntArray:array offset:0 skip:1 numBytes:numBytes];
}

-(void)writeTaggedInteger:(long)anInt
{
    unsigned char buffer[16];
    int log2ofNumBytes=2;
    int numBytes=4;
    buffer[0]=0x10 + log2ofNumBytes;
    for (int i=numBytes-1;i>=0;i--) {
        buffer[i+1]=anInt & 0xff;
        anInt>>=8;
    }
    TARGET_APPEND(buffer, numBytes+1);
}


-(void)writeHeader:(int)headerByte length:(int)length
{
    unsigned char header=headerByte;
    if ( length < 15 ) {
        header=header | length;
        TARGET_APPEND(&header, 1);
    } else {
        header=header | 0xf;
        TARGET_APPEND(&header, 1);
        [self writeTaggedInteger:length];
    }
}

-(void)writeInt:(int)anInteger forKey:(NSString*)aKey
{
    [self writeString:aKey];
    [self writeInteger:anInteger];
}

-(void)writeFloat:(float)aFloat forKey:(NSString*)aKey
{
    [self writeString:aKey];
    [self writeFloat:aFloat];
}

-(void)writeObject:(id)anObject forKey:(NSString*)aKey
{
    [self writeString:aKey];
    [self writeObject:anObject];
}

-(void)endArray
{
    @autoreleasepool {
        MPWIntArray *arrayIndexes=[self popIndexStack];
        [self _recordByteOffset];
        [self writeHeader:0xa0 length:[arrayIndexes count]];
        [self writeIntArray:arrayIndexes numBytes:inlineOffsetByteSize];
    }
}


-(void)endDictionary
{

    MPWIntArray *arrayIndexes=[self popIndexStack];
    [self _recordByteOffset];
    int len=[arrayIndexes count]/2;
    [self writeHeader:0xd0 length:len];
    [self writeIntArray:arrayIndexes offset:0 skip:2 numBytes:inlineOffsetByteSize];
    [self writeIntArray:arrayIndexes offset:1 skip:2 numBytes:inlineOffsetByteSize];
}


-(void)writeHeader
{
    if ( !headerWritten) {
        TARGET_APPEND("bplist00", 8);
        headerWritten=YES;
    }
}

-(void)_recordByteOffset
{
    
    [currentIndexes addInteger:[offsets count]];
    [offsets addInteger:totalBytes];
}

-(int)currentObjectIndex
{
    return [offsets count];
}


-(void)writeInteger:(long)anInt
{
    unsigned char buffer[16];
    int log2ofNumBytes=2;
    int numBytes=4;
    [self _recordByteOffset];
    buffer[0]=0x10 + log2ofNumBytes;
    for (int i=numBytes-1;i>=0;i--) {
        buffer[i+1]=anInt & 0xff;
        anInt>>=8;
    }
    TARGET_APPEND(buffer, numBytes+1);
}

-(void)writeFloat:(float)aFloat
{
    unsigned char buffer[16];
    int log2ofNumBytes=2;
    int numBytes=4;
    unsigned char *floatPtr=(unsigned char*)&aFloat;
    [self _recordByteOffset];
    buffer[0]=0x20 + log2ofNumBytes;
    for (int i=0;i<numBytes;i++) {
        buffer[i+1]=floatPtr[numBytes-i-1];
    }
    TARGET_APPEND(buffer, numBytes+1);
}

-(void)writeString:(NSString*)aString
{
    int offset=0;
    offset=(int)[objectTable objectForKey:aString];
    
    if ( offset ) {
        [currentIndexes addInteger:offset];
    } else {
        [self _recordByteOffset];
        int l=[aString length];
        char buffer[ l + 1];
        [aString getBytes:buffer maxLength:l usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:NSMakeRange(0, l) remainingRange:NULL];
        [self writeHeader:0x50 length:[aString length]];
        TARGET_APPEND(buffer, l);
        [objectTable setObject:(id)(long)[currentIndexes lastInteger] forKey:aString];
    }
}

-(int)offsetTableEntryByteSize
{
    return 4;
}

-(void)writeOffsetTable
{
    offsetOfOffsetTable=[self length];
//    NSLog(@"offsets: %@",offsets);
    [self writeIntArray:offsets numBytes:[self offsetTableEntryByteSize]];
}

-(long)count
{
    return [offsets count];
}

-(long)rootObjectIndex
{
    return [self currentObjectIndex]-1;
}

-(void)writeTrailer
{
    TARGET_APPEND("\0\0\0\0\0\0", 6);
    [self writeInteger:[self offsetTableEntryByteSize] numBytes:1];
    [self writeInteger:inlineOffsetByteSize numBytes:1];
    [self writeInteger:[self count] numBytes:8]; // num objs in table
    [self writeInteger:[self rootObjectIndex] numBytes:8];       // root
    [self writeInteger:offsetOfOffsetTable numBytes:8];       // root
}

-(void)flushLocal
{
//    NSLog(@"writeOffsetTable: %@",offsets);
    [self writeOffsetTable];
//    NSLog(@"writeTrailer");
    [self writeTrailer];
}

-(void)dealloc
{
    [indexStack release];
    [offsets release];
    [reserveIndexes release];
    [objectTable release];
    [super dealloc];
}

@end


#import "DebugMacros.h"

@implementation MPWBinaryPListWriter(tests)

+_plistForData:(NSData*)d
{
    id plist=[NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:nil];
    return plist;
}

+_plistForStream:(MPWBinaryPListWriter*)aStream
{
    return [self _plistForData:[aStream target]];
}

+_plistViaStream:(id)aPlist
{
    return [self _plistForData:[self process:aPlist]];
}

+(void)testHeaderWrittenAutomaticallyAndIgnoredAfter
{
    MPWBinaryPListWriter *writer=[self stream];
    INTEXPECT( [[writer target] length],8,@"data written before");
    INTEXPECT([writer length], 8, @"bytes written before");
    [writer writeHeader];
    INTEXPECT([writer length], 8, @"bytes written after header");
}


+(void)testWriteSingleIntegerValue
{
    MPWBinaryPListWriter *writer=[self stream];
    [writer writeInteger:42];
    INTEXPECT([[writer offsets] count], 1, @"should have recored an offset");
    INTEXPECT([[writer offsets] integerAtIndex:0], 8, @"offset of first object");
    [writer flush];
    //    [[writer target] writeToFile:@"/tmp/fourtytwo.plist" atomically:YES];
    NSNumber *n=[self _plistForStream:writer];
    INTEXPECT([n intValue], 42, @"encoded plist value");
}


+(void)testWriteSingleFloatValue
{
    MPWBinaryPListWriter *writer=[self stream];
    [writer writeFloat:3.14159];
    [writer close];
    NSNumber *n=[self _plistForStream:writer];
    FLOATEXPECTTOLERANCE([n floatValue], 3.14159, 0.000001, @"encoded");
}


+(void)testWriteArrayWithTwoElements
{
    MPWBinaryPListWriter *writer=[self stream];
    [writer writeHeader];
    [writer beginArray];
    [writer writeInteger:31];
    [writer writeInteger:42];
    [writer endArray];
    [writer flush];
//    [[writer target] writeToFile:@"/tmp/fourtytwo-array.plist" atomically:YES];
    NSArray *a=[self _plistForStream:writer];
//    NSLog(@"a: %@",a);
    INTEXPECT([a count], 2, @"array with 2 values");
    INTEXPECT([[a objectAtIndex:0] intValue], 31, @"array with 2 values");
    INTEXPECT([[a lastObject] intValue], 42, @"array with 2 values");
}

+(void)testWriteNestedArray
{
    MPWBinaryPListWriter *writer=[self stream];
    [writer writeHeader];
    [writer beginArray];
    [writer writeInteger:31];
    [writer beginArray];
    [writer writeInteger:51];
    [writer writeInteger:123];
    [writer endArray];
    [writer writeInteger:42];
    [writer endArray];
    [writer flush];
//    [[writer target] writeToFile:@"/tmp/nested-array.plist" atomically:YES];
    NSArray *a=[self _plistForStream:writer];
//    NSLog(@"a: %@",a);
    INTEXPECT([a count], 3, @"top level array count");
    NSArray *nested=[a objectAtIndex:1];
    INTEXPECT([nested count], 2, @"nested array count");
    INTEXPECT([[a objectAtIndex:0] intValue], 31, @"array with 2 values");
    INTEXPECT([[a lastObject] intValue], 42, @"array with 2 values");
    INTEXPECT([[nested objectAtIndex:0] intValue], 51, @"array with 2 values");
    INTEXPECT([[nested lastObject] intValue], 123, @"array with 2 values");
}

+(void)testWriteString
{
    MPWBinaryPListWriter *writer=[self stream];
    [writer writeHeader];
    [writer writeString:@"Hello World!"];
    [writer flush];
    NSString *s=[self _plistForStream:writer];
    IDEXPECT(s , @"Hello World!", @"the string I wrote");
}



+(void)testArrayWithStringsAndInts
{
    MPWBinaryPListWriter *writer=[self stream];
    [writer beginArray];
    [writer writeString:@"What's up doc?"];
    [writer beginArray];
    [writer writeInteger:51];
    [writer writeString:@"nested"];
    [writer endArray];
    [writer writeInteger:42];
    [writer endArray];
    [writer flush];
    //    [[writer target] writeToFile:@"/tmp/nested-array.plist" atomically:YES];
    NSArray *a=[self _plistForStream:writer];
    //    NSLog(@"a: %@",a);
    INTEXPECT([a count], 3, @"top level array count");
    NSArray *nested=[a objectAtIndex:1];
    INTEXPECT([nested count], 2, @"nested array count");
    IDEXPECT([a objectAtIndex:0], @"What's up doc?", @"array with 2 values");
    INTEXPECT([[a lastObject] intValue], 42, @"array with 2 values");
    INTEXPECT([[nested objectAtIndex:0] intValue], 51, @"array with 2 values");
    IDEXPECT([nested lastObject], @"nested", @"array with 2 values");
}


+(void)testSimpleDict
{
    MPWBinaryPListWriter *writer=[self stream];
    [writer beginDictionary];
    [writer writeInt:42 forKey:@"theAnswer"];
    [writer endDictionary];
    [writer flush];
    //    [[writer target] writeToFile:@"/tmp/nested-array.plist" atomically:YES];
    NSDictionary *a=[self _plistForStream:writer];
    INTEXPECT([a count], 1, @"size of dict");
    IDEXPECT([a objectForKey:@"theAnswer"], @42, @"theAnswer");
    //    NSLog(@"a: %@",a);
}



+(void)testArrayWriter
{
    MPWBinaryPListWriter *writer=[self stream];
    NSArray *argument=@[ @1 , @5, @52 ];
    [writer writeArray:argument usingElementBlock:^(MPWBinaryPListWriter* writer,id randomArgument){
        [writer writeInteger:[randomArgument intValue]];
    }];
    [writer flush];
    NSArray *a=[self _plistForStream:writer];
    INTEXPECT([a count], 3, @"size of array");
    IDEXPECT([a lastObject], @52, @"theAnswer");
    //    NSLog(@"a: %@",a);
}


+(void)testLargerArray
{
    MPWBinaryPListWriter *writer=[self stream];
    NSMutableArray *input=[NSMutableArray array];
    for (int i=0;i<15;i++) {
        [input addObject:@(i)];
    }
    [writer writeArray:input usingElementBlock:^(MPWBinaryPListWriter* writer,id randomArgument){
        [writer writeInteger:[randomArgument intValue]];
    }];
    [writer close];
    NSArray *a=[self _plistForStream:writer];
    INTEXPECT([a count], 15, @"size of array");
    IDEXPECT([a lastObject], @14, @"theAnswer");
    //    NSLog(@"a: %@",a);
}

+(void)testWriteObjectAndStreamMessage
{
    IDEXPECT([self _plistViaStream:@"Hello World!"], @"Hello World!",@"process single string");

    INTEXPECT([[self _plistViaStream:@42] intValue], 42,@"process single integer");
    FLOATEXPECTTOLERANCE([[self _plistViaStream:@3.14159] floatValue], 3.14159,0.001,@"process single float");

}

+(void)testWriteWriteGenericArray
{
    NSArray *a=@[ @"abced", @42, @2.713 ];
    NSArray *result=[self _plistViaStream:a];
    INTEXPECT([result count], 3, @"result count");
}

+(void)testWriteWriteGenericDictionary
{
    NSDictionary *a=@{ @"a": @"hello world", @"b": @42 };
    NSArray *result=[self _plistViaStream:a];
    INTEXPECT([result count], 2, @"result count");
}

+testSelectors
{
    return @[
             @"testHeaderWrittenAutomaticallyAndIgnoredAfter",
             @"testWriteSingleIntegerValue",
             @"testWriteSingleFloatValue",
             @"testWriteArrayWithTwoElements",
             @"testWriteNestedArray",
             @"testWriteString",
             @"testArrayWithStringsAndInts",
             @"testSimpleDict",
             @"testArrayWriter",
             @"testLargerArray",
             @"testWriteObjectAndStreamMessage",
             @"testWriteWriteGenericArray",
             @"testWriteWriteGenericDictionary",
             ];
}

@end

@implementation NSObject(plistWriting)


-(void)writeOnPlist:(MPWBinaryPListWriter*)aPlist
{
    [self writeOnByteStream:aPlist];
}

@end

@implementation NSNumber(plistWriting)

-(void)writeOnPlist:(MPWBinaryPListWriter*)aPlist
{
    if ( CFNumberIsFloatType( (CFNumberRef)self) ) {
        [aPlist writeFloat:[self floatValue]];
    } else {
        [aPlist writeInteger:[self longValue]];
    }
}


@end



; ModuleID = 'blink_formal_engine.c'
source_filename = "blink_formal_engine.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx27.0.0"

%struct.InteractivePageInput = type { i64, %struct.MarginBox, i64, %struct.MarginBox, i64, i64, %struct.MarginBox, i64, i64, i64, %struct.MarginBox, i64, %struct.MarginBox, i64, i64, i64, i64, %struct.MarginBox }
%struct.MarginBox = type { i64, i64 }
%struct.InteractiveLayoutOutput = type { i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64 }
%struct.Color = type { i8, i8, i8, i8 }

@__const.get_sample_interactive_page.page = private unnamed_addr constant %struct.InteractivePageInput { i64 38, %struct.MarginBox { i64 21, i64 21 }, i64 19, %struct.MarginBox { i64 16, i64 16 }, i64 2, i64 30, %struct.MarginBox { i64 12, i64 12 }, i64 40, i64 60, i64 25, %struct.MarginBox { i64 10, i64 10 }, i64 40, %struct.MarginBox { i64 16, i64 16 }, i64 60, i64 16, i64 6, i64 2, %struct.MarginBox { i64 10, i64 10 } }, align 8
@.str = private unnamed_addr constant [3 x i8] c"wb\00", align 1
@.str.1 = private unnamed_addr constant [18 x i8] c"P6\0A%lld %lld\0A255\0A\00", align 1

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync)
define noundef i64 @collapse_margins(i64 noundef %0, i64 noundef %1) local_unnamed_addr #0 {
  %3 = tail call i64 @llvm.smax.i64(i64 %0, i64 %1)
  ret i64 %3
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync)
define range(i64 -92233720368547758, 92233720368547759) i64 @resolve_percent_col_width(i64 noundef %0, i64 noundef %1) local_unnamed_addr #0 {
  %3 = mul nsw i64 %1, %0
  %4 = sdiv i64 %3, 100
  ret i64 %4
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync)
define noundef i64 @button_inline_size(i64 noundef %0, i64 noundef %1, i64 noundef %2, i64 noundef %3) local_unnamed_addr #0 {
  %5 = add i64 %2, %1
  %6 = shl i64 %5, 1
  %7 = add i64 %6, %0
  %8 = icmp sgt i64 %3, 0
  %9 = select i1 %8, i64 %3, i64 %7
  ret i64 %9
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync)
define noundef i64 @button_block_size(i64 noundef %0, i64 noundef %1, i64 noundef %2, i64 noundef %3) local_unnamed_addr #0 {
  %5 = add i64 %2, %1
  %6 = shl i64 %5, 1
  %7 = add i64 %6, %0
  %8 = icmp sgt i64 %3, 0
  %9 = select i1 %8, i64 %3, i64 %7
  ret i64 %9
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: readwrite) uwtable(sync)
define void @get_sample_interactive_page(ptr dead_on_unwind noalias writable writeonly sret(%struct.InteractivePageInput) align 8 captures(none) initializes((0, 192)) %0) local_unnamed_addr #1 {
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(192) %0, ptr noundef nonnull align 8 dereferenceable(192) @__const.get_sample_interactive_page.page, i64 192, i1 false)
  ret void
}

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #2

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: readwrite) uwtable(sync)
define void @layout_interactive_page_pipeline(ptr dead_on_unwind noalias writable writeonly sret(%struct.InteractiveLayoutOutput) align 8 captures(none) initializes((0, 136)) %0, i64 noundef %1, i64 noundef %2, ptr noundef readonly captures(none) %3) local_unnamed_addr #1 {
  %5 = getelementptr inbounds nuw i8, ptr %3, i64 8
  %6 = load i64, ptr %5, align 8, !tbaa !6
  %7 = add nsw i64 %6, 8
  %8 = load i64, ptr %3, align 8, !tbaa !12
  %9 = getelementptr inbounds nuw i8, ptr %3, i64 16
  %10 = load i64, ptr %9, align 8, !tbaa !13
  %11 = getelementptr inbounds nuw i8, ptr %3, i64 32
  %12 = load i64, ptr %11, align 8, !tbaa !14
  %13 = tail call noundef i64 @llvm.smax.i64(i64 %10, i64 %12)
  %14 = add nsw i64 %7, %8
  %15 = add nsw i64 %14, %13
  %16 = getelementptr inbounds nuw i8, ptr %3, i64 24
  %17 = load i64, ptr %16, align 8, !tbaa !15
  %18 = getelementptr inbounds nuw i8, ptr %3, i64 40
  %19 = load i64, ptr %18, align 8, !tbaa !16
  %20 = getelementptr inbounds nuw i8, ptr %3, i64 64
  %21 = load i64, ptr %20, align 8, !tbaa !17
  %22 = tail call noundef i64 @llvm.smax.i64(i64 %19, i64 %21)
  %23 = add nsw i64 %15, %17
  %24 = add nsw i64 %23, %22
  %25 = getelementptr inbounds nuw i8, ptr %3, i64 48
  %26 = load i64, ptr %25, align 8, !tbaa !18
  %27 = getelementptr inbounds nuw i8, ptr %3, i64 56
  %28 = load i64, ptr %27, align 8, !tbaa !19
  %29 = mul nsw i64 %28, %26
  %30 = getelementptr inbounds nuw i8, ptr %3, i64 72
  %31 = load i64, ptr %30, align 8, !tbaa !20
  %32 = getelementptr inbounds nuw i8, ptr %3, i64 104
  %33 = load i64, ptr %32, align 8, !tbaa !21
  %34 = tail call noundef i64 @llvm.smax.i64(i64 %31, i64 %33)
  %35 = add nsw i64 %29, %24
  %36 = add nsw i64 %35, %34
  %37 = getelementptr inbounds nuw i8, ptr %3, i64 96
  %38 = load i64, ptr %37, align 8, !tbaa !22
  %39 = add nsw i64 %1, -16
  %40 = getelementptr inbounds nuw i8, ptr %3, i64 80
  %41 = load i64, ptr %40, align 8, !tbaa !23
  %42 = mul nsw i64 %41, %39
  %43 = sdiv i64 %42, 100
  %44 = getelementptr inbounds nuw i8, ptr %3, i64 88
  %45 = load i64, ptr %44, align 8, !tbaa !24
  %46 = mul nsw i64 %45, %39
  %47 = sdiv i64 %46, 100
  %48 = getelementptr inbounds nuw i8, ptr %3, i64 112
  %49 = load i64, ptr %48, align 8, !tbaa !25
  %50 = getelementptr inbounds nuw i8, ptr %3, i64 128
  %51 = load i64, ptr %50, align 8, !tbaa !26
  %52 = tail call noundef i64 @llvm.smax.i64(i64 %49, i64 %51)
  %53 = add nsw i64 %36, %38
  %54 = add nsw i64 %53, %52
  %55 = getelementptr inbounds nuw i8, ptr %3, i64 120
  %56 = load i64, ptr %55, align 8, !tbaa !27
  %57 = getelementptr inbounds nuw i8, ptr %3, i64 136
  %58 = load i64, ptr %57, align 8, !tbaa !28
  %59 = getelementptr inbounds nuw i8, ptr %3, i64 176
  %60 = load i64, ptr %59, align 8, !tbaa !29
  %61 = tail call noundef i64 @llvm.smax.i64(i64 %58, i64 %60)
  %62 = add nsw i64 %54, %56
  %63 = add nsw i64 %62, %61
  %64 = getelementptr inbounds nuw i8, ptr %3, i64 160
  %65 = load i64, ptr %64, align 8, !tbaa !30
  %66 = getelementptr inbounds nuw i8, ptr %3, i64 168
  %67 = load i64, ptr %66, align 8, !tbaa !31
  %68 = getelementptr inbounds nuw i8, ptr %3, i64 144
  %69 = add i64 %67, %65
  %70 = shl i64 %69, 1
  store i64 %1, ptr %0, align 8, !tbaa !32
  %71 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 %2, ptr %71, align 8, !tbaa !34
  %72 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 %7, ptr %72, align 8, !tbaa !35
  %73 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 %8, ptr %73, align 8, !tbaa !36
  %74 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 %15, ptr %74, align 8, !tbaa !37
  %75 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store i64 %17, ptr %75, align 8, !tbaa !38
  %76 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store i64 %24, ptr %76, align 8, !tbaa !39
  %77 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 %29, ptr %77, align 8, !tbaa !40
  %78 = getelementptr inbounds nuw i8, ptr %0, i64 64
  store i64 %36, ptr %78, align 8, !tbaa !41
  %79 = getelementptr inbounds nuw i8, ptr %0, i64 72
  store i64 %38, ptr %79, align 8, !tbaa !42
  %80 = getelementptr inbounds nuw i8, ptr %0, i64 80
  store i64 %43, ptr %80, align 8, !tbaa !43
  %81 = getelementptr inbounds nuw i8, ptr %0, i64 88
  store i64 %47, ptr %81, align 8, !tbaa !44
  %82 = getelementptr inbounds nuw i8, ptr %0, i64 96
  store i64 %54, ptr %82, align 8, !tbaa !45
  %83 = getelementptr inbounds nuw i8, ptr %0, i64 104
  store i64 %56, ptr %83, align 8, !tbaa !46
  %84 = getelementptr inbounds nuw i8, ptr %0, i64 112
  store i64 %63, ptr %84, align 8, !tbaa !47
  %85 = getelementptr inbounds nuw i8, ptr %0, i64 120
  %86 = load <2 x i64>, ptr %68, align 8, !tbaa !48
  %87 = insertelement <2 x i64> poison, i64 %70, i64 0
  %88 = shufflevector <2 x i64> %87, <2 x i64> poison, <2 x i32> zeroinitializer
  %89 = add <2 x i64> %88, %86
  store <2 x i64> %89, ptr %85, align 8, !tbaa !48
  ret void
}

; Function Attrs: nounwind ssp memory(readwrite, argmem: none) uwtable(sync)
define noalias noundef ptr @fb_create(i64 noundef %0, i64 noundef %1, i64 %2) local_unnamed_addr #3 {
  %4 = trunc i64 %2 to i32
  %5 = tail call dereferenceable_or_null(24) ptr @malloc(i64 noundef 24) #13
  %6 = icmp eq ptr %5, null
  br i1 %6, label %58, label %7

7:                                                ; preds = %3
  store i64 %0, ptr %5, align 8, !tbaa !49
  %8 = getelementptr inbounds nuw i8, ptr %5, i64 8
  store i64 %1, ptr %8, align 8, !tbaa !52
  %9 = shl i64 %0, 2
  %10 = mul i64 %9, %1
  %11 = tail call ptr @malloc(i64 noundef %10) #13
  %12 = getelementptr inbounds nuw i8, ptr %5, i64 16
  store ptr %11, ptr %12, align 8, !tbaa !53
  %13 = icmp eq ptr %11, null
  br i1 %13, label %52, label %14

14:                                               ; preds = %7
  %15 = mul nsw i64 %1, %0
  %16 = icmp sgt i64 %15, 0
  br i1 %16, label %17, label %58

17:                                               ; preds = %14
  %18 = icmp samesign ult i64 %15, 4
  br i1 %18, label %19, label %21

19:                                               ; preds = %37, %50, %17
  %20 = phi i64 [ 0, %17 ], [ %24, %37 ], [ %42, %50 ]
  br label %53

21:                                               ; preds = %17
  %22 = icmp samesign ult i64 %15, 16
  br i1 %22, label %40, label %23

23:                                               ; preds = %21
  %24 = and i64 %15, 9223372036854775792
  %25 = insertelement <4 x i32> poison, i32 %4, i64 0
  %26 = shufflevector <4 x i32> %25, <4 x i32> poison, <4 x i32> zeroinitializer
  br label %27

27:                                               ; preds = %27, %23
  %28 = phi i64 [ 0, %23 ], [ %33, %27 ]
  %29 = getelementptr inbounds nuw %struct.Color, ptr %11, i64 %28
  %30 = getelementptr inbounds nuw i8, ptr %29, i64 16
  %31 = getelementptr inbounds nuw i8, ptr %29, i64 32
  %32 = getelementptr inbounds nuw i8, ptr %29, i64 48
  store <4 x i32> %26, ptr %29, align 1
  store <4 x i32> %26, ptr %30, align 1
  store <4 x i32> %26, ptr %31, align 1
  store <4 x i32> %26, ptr %32, align 1
  %33 = add nuw i64 %28, 16
  %34 = icmp eq i64 %33, %24
  br i1 %34, label %35, label %27, !llvm.loop !54

35:                                               ; preds = %27
  %36 = icmp eq i64 %15, %24
  br i1 %36, label %58, label %37

37:                                               ; preds = %35
  %38 = and i64 %15, 12
  %39 = icmp eq i64 %38, 0
  br i1 %39, label %19, label %40

40:                                               ; preds = %37, %21
  %41 = phi i64 [ %24, %37 ], [ 0, %21 ]
  %42 = and i64 %15, 9223372036854775804
  %43 = insertelement <4 x i32> poison, i32 %4, i64 0
  %44 = shufflevector <4 x i32> %43, <4 x i32> poison, <4 x i32> zeroinitializer
  br label %45

45:                                               ; preds = %45, %40
  %46 = phi i64 [ %41, %40 ], [ %48, %45 ]
  %47 = getelementptr inbounds nuw %struct.Color, ptr %11, i64 %46
  store <4 x i32> %44, ptr %47, align 1
  %48 = add nuw i64 %46, 4
  %49 = icmp eq i64 %48, %42
  br i1 %49, label %50, label %45, !llvm.loop !58

50:                                               ; preds = %45
  %51 = icmp eq i64 %15, %42
  br i1 %51, label %58, label %19

52:                                               ; preds = %7
  tail call void @free(ptr noundef nonnull %5)
  br label %58

53:                                               ; preds = %19, %53
  %54 = phi i64 [ %56, %53 ], [ %20, %19 ]
  %55 = getelementptr inbounds nuw %struct.Color, ptr %11, i64 %54
  store i32 %4, ptr %55, align 1
  %56 = add nuw nsw i64 %54, 1
  %57 = icmp eq i64 %56, %15
  br i1 %57, label %58, label %53, !llvm.loop !59

58:                                               ; preds = %53, %35, %50, %14, %3, %52
  %59 = phi ptr [ null, %52 ], [ null, %3 ], [ %5, %14 ], [ %5, %50 ], [ %5, %35 ], [ %5, %53 ]
  ret ptr %59
}

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite)
declare noalias noundef ptr @malloc(i64 noundef) local_unnamed_addr #4

; Function Attrs: mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite)
declare void @free(ptr allocptr noundef captures(none)) local_unnamed_addr #5

; Function Attrs: mustprogress nounwind ssp willreturn uwtable(sync)
define void @fb_destroy(ptr noundef captures(address_is_null) %0) local_unnamed_addr #6 {
  %2 = icmp eq ptr %0, null
  br i1 %2, label %9, label %3

3:                                                ; preds = %1
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %5 = load ptr, ptr %4, align 8, !tbaa !53
  %6 = icmp eq ptr %5, null
  br i1 %6, label %8, label %7

7:                                                ; preds = %3
  tail call void @free(ptr noundef nonnull %5)
  br label %8

8:                                                ; preds = %7, %3
  tail call void @free(ptr noundef nonnull %0)
  br label %9

9:                                                ; preds = %8, %1
  ret void
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(write, argmem: readwrite, inaccessiblemem: none) uwtable(sync)
define void @fb_fill_rect(ptr noundef readonly captures(address_is_null) %0, i64 noundef %1, i64 noundef %2, i64 noundef %3, i64 noundef %4, i64 %5) local_unnamed_addr #7 {
  %7 = trunc i64 %5 to i32
  %8 = icmp eq ptr %0, null
  br i1 %8, label %40, label %9

9:                                                ; preds = %6
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %11 = load ptr, ptr %10, align 8, !tbaa !53
  %12 = icmp eq ptr %11, null
  br i1 %12, label %40, label %13

13:                                               ; preds = %9
  %14 = tail call i64 @llvm.smax.i64(i64 %1, i64 0)
  %15 = tail call i64 @llvm.smax.i64(i64 %2, i64 0)
  %16 = add i64 %3, %1
  %17 = load i64, ptr %0, align 8, !tbaa !49
  %18 = tail call i64 @llvm.smin.i64(i64 %16, i64 %17)
  %19 = add nsw i64 %4, %2
  %20 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %21 = load i64, ptr %20, align 8, !tbaa !52
  %22 = tail call i64 @llvm.smin.i64(i64 %19, i64 %21)
  %23 = icmp slt i64 %15, %22
  %24 = icmp slt i64 %14, %18
  %25 = select i1 %23, i1 %24, i1 false
  br i1 %25, label %26, label %40

26:                                               ; preds = %13, %37
  %27 = phi i64 [ %38, %37 ], [ %15, %13 ]
  br label %28

28:                                               ; preds = %26, %28
  %29 = phi i64 [ %14, %26 ], [ %35, %28 ]
  %30 = load ptr, ptr %10, align 8, !tbaa !53
  %31 = load i64, ptr %0, align 8, !tbaa !49
  %32 = mul nsw i64 %31, %27
  %33 = getelementptr %struct.Color, ptr %30, i64 %32
  %34 = getelementptr %struct.Color, ptr %33, i64 %29
  store i32 %7, ptr %34, align 1
  %35 = add nuw nsw i64 %29, 1
  %36 = icmp eq i64 %35, %18
  br i1 %36, label %37, label %28, !llvm.loop !60

37:                                               ; preds = %28
  %38 = add nuw nsw i64 %27, 1
  %39 = icmp eq i64 %38, %22
  br i1 %39, label %40, label %26, !llvm.loop !61

40:                                               ; preds = %37, %13, %6, %9
  ret void
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(write, argmem: readwrite, inaccessiblemem: none) uwtable(sync)
define void @fb_draw_border(ptr noundef readonly captures(address_is_null) %0, i64 noundef %1, i64 noundef %2, i64 noundef %3, i64 noundef %4, i64 noundef %5, i64 %6) local_unnamed_addr #7 {
  %8 = icmp eq ptr %0, null
  br i1 %8, label %128, label %9

9:                                                ; preds = %7
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %11 = load ptr, ptr %10, align 8, !tbaa !53
  %12 = icmp eq ptr %11, null
  %13 = icmp slt i64 %5, 1
  %14 = or i1 %13, %12
  br i1 %14, label %128, label %15

15:                                               ; preds = %9
  %16 = trunc i64 %6 to i32
  %17 = tail call i64 @llvm.smax.i64(i64 %1, i64 0)
  %18 = tail call i64 @llvm.smax.i64(i64 %2, i64 0)
  %19 = add i64 %3, %1
  %20 = load i64, ptr %0, align 8, !tbaa !49
  %21 = tail call i64 @llvm.smin.i64(i64 %19, i64 %20)
  %22 = add nsw i64 %5, %2
  %23 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %24 = load i64, ptr %23, align 8, !tbaa !52
  %25 = tail call i64 @llvm.smin.i64(i64 %22, i64 %24)
  %26 = icmp slt i64 %18, %25
  %27 = icmp slt i64 %17, %21
  %28 = select i1 %26, i1 %27, i1 false
  br i1 %28, label %29, label %46

29:                                               ; preds = %15, %40
  %30 = phi i64 [ %41, %40 ], [ %18, %15 ]
  br label %31

31:                                               ; preds = %31, %29
  %32 = phi i64 [ %17, %29 ], [ %38, %31 ]
  %33 = load ptr, ptr %10, align 8, !tbaa !53
  %34 = load i64, ptr %0, align 8, !tbaa !49
  %35 = mul nsw i64 %34, %30
  %36 = getelementptr %struct.Color, ptr %33, i64 %35
  %37 = getelementptr %struct.Color, ptr %36, i64 %32
  store i32 %16, ptr %37, align 1
  %38 = add nuw nsw i64 %32, 1
  %39 = icmp eq i64 %38, %21
  br i1 %39, label %40, label %31, !llvm.loop !60

40:                                               ; preds = %31
  %41 = add nuw nsw i64 %30, 1
  %42 = icmp eq i64 %41, %25
  br i1 %42, label %43, label %29, !llvm.loop !61

43:                                               ; preds = %40
  %44 = load ptr, ptr %10, align 8, !tbaa !53
  %45 = icmp eq ptr %44, null
  br i1 %45, label %128, label %46

46:                                               ; preds = %15, %43
  %47 = add nsw i64 %4, %2
  %48 = sub nsw i64 %47, %5
  %49 = tail call i64 @llvm.smax.i64(i64 %48, i64 0)
  %50 = load i64, ptr %0, align 8, !tbaa !49
  %51 = tail call i64 @llvm.smin.i64(i64 %19, i64 %50)
  %52 = load i64, ptr %23, align 8, !tbaa !52
  %53 = tail call i64 @llvm.smin.i64(i64 %47, i64 %52)
  %54 = icmp slt i64 %49, %53
  %55 = icmp slt i64 %17, %51
  %56 = select i1 %54, i1 %55, i1 false
  br i1 %56, label %57, label %74

57:                                               ; preds = %46, %68
  %58 = phi i64 [ %69, %68 ], [ %49, %46 ]
  br label %59

59:                                               ; preds = %59, %57
  %60 = phi i64 [ %17, %57 ], [ %66, %59 ]
  %61 = load ptr, ptr %10, align 8, !tbaa !53
  %62 = load i64, ptr %0, align 8, !tbaa !49
  %63 = mul nsw i64 %62, %58
  %64 = getelementptr %struct.Color, ptr %61, i64 %63
  %65 = getelementptr %struct.Color, ptr %64, i64 %60
  store i32 %16, ptr %65, align 1
  %66 = add nuw nsw i64 %60, 1
  %67 = icmp eq i64 %66, %51
  br i1 %67, label %68, label %59, !llvm.loop !60

68:                                               ; preds = %59
  %69 = add nuw nsw i64 %58, 1
  %70 = icmp eq i64 %69, %53
  br i1 %70, label %71, label %57, !llvm.loop !61

71:                                               ; preds = %68
  %72 = load ptr, ptr %10, align 8, !tbaa !53
  %73 = icmp eq ptr %72, null
  br i1 %73, label %128, label %74

74:                                               ; preds = %46, %71
  %75 = shl nuw nsw i64 %5, 1
  %76 = sub nsw i64 %4, %75
  %77 = tail call i64 @llvm.smax.i64(i64 %22, i64 0)
  %78 = add i64 %5, %1
  %79 = load i64, ptr %0, align 8, !tbaa !49
  %80 = tail call i64 @llvm.smin.i64(i64 %78, i64 %79)
  %81 = add nsw i64 %76, %22
  %82 = load i64, ptr %23, align 8, !tbaa !52
  %83 = tail call i64 @llvm.smin.i64(i64 %81, i64 %82)
  %84 = icmp slt i64 %77, %83
  %85 = icmp slt i64 %17, %80
  %86 = select i1 %84, i1 %85, i1 false
  br i1 %86, label %87, label %104

87:                                               ; preds = %74, %98
  %88 = phi i64 [ %99, %98 ], [ %77, %74 ]
  br label %89

89:                                               ; preds = %89, %87
  %90 = phi i64 [ %17, %87 ], [ %96, %89 ]
  %91 = load ptr, ptr %10, align 8, !tbaa !53
  %92 = load i64, ptr %0, align 8, !tbaa !49
  %93 = mul nsw i64 %92, %88
  %94 = getelementptr %struct.Color, ptr %91, i64 %93
  %95 = getelementptr %struct.Color, ptr %94, i64 %90
  store i32 %16, ptr %95, align 1
  %96 = add nuw nsw i64 %90, 1
  %97 = icmp eq i64 %96, %80
  br i1 %97, label %98, label %89, !llvm.loop !60

98:                                               ; preds = %89
  %99 = add nuw nsw i64 %88, 1
  %100 = icmp eq i64 %99, %83
  br i1 %100, label %101, label %87, !llvm.loop !61

101:                                              ; preds = %98
  %102 = load ptr, ptr %10, align 8, !tbaa !53
  %103 = icmp eq ptr %102, null
  br i1 %103, label %128, label %104

104:                                              ; preds = %74, %101
  %105 = sub nsw i64 %19, %5
  %106 = tail call i64 @llvm.smax.i64(i64 %105, i64 0)
  %107 = load i64, ptr %0, align 8, !tbaa !49
  %108 = tail call i64 @llvm.smin.i64(i64 %19, i64 %107)
  %109 = load i64, ptr %23, align 8, !tbaa !52
  %110 = tail call i64 @llvm.smin.i64(i64 %81, i64 %109)
  %111 = icmp slt i64 %77, %110
  %112 = icmp slt i64 %106, %108
  %113 = select i1 %111, i1 %112, i1 false
  br i1 %113, label %114, label %128

114:                                              ; preds = %104, %125
  %115 = phi i64 [ %126, %125 ], [ %77, %104 ]
  br label %116

116:                                              ; preds = %116, %114
  %117 = phi i64 [ %106, %114 ], [ %123, %116 ]
  %118 = load ptr, ptr %10, align 8, !tbaa !53
  %119 = load i64, ptr %0, align 8, !tbaa !49
  %120 = mul nsw i64 %119, %115
  %121 = getelementptr %struct.Color, ptr %118, i64 %120
  %122 = getelementptr %struct.Color, ptr %121, i64 %117
  store i32 %16, ptr %122, align 1
  %123 = add nuw nsw i64 %117, 1
  %124 = icmp eq i64 %123, %108
  br i1 %124, label %125, label %116, !llvm.loop !60

125:                                              ; preds = %116
  %126 = add nuw nsw i64 %115, 1
  %127 = icmp eq i64 %126, %110
  br i1 %127, label %128, label %114, !llvm.loop !61

128:                                              ; preds = %125, %43, %71, %104, %101, %7, %9
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(read, inaccessiblemem: none) uwtable(sync)
define i32 @fb_get_pixel(ptr noundef readonly captures(address_is_null) %0, i64 noundef %1, i64 noundef %2) local_unnamed_addr #8 {
  %4 = icmp eq ptr %0, null
  br i1 %4, label %25, label %5

5:                                                ; preds = %3
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %7 = load ptr, ptr %6, align 8, !tbaa !53
  %8 = icmp eq ptr %7, null
  %9 = icmp slt i64 %1, 0
  %10 = or i1 %9, %8
  br i1 %10, label %25, label %11

11:                                               ; preds = %5
  %12 = load i64, ptr %0, align 8, !tbaa !49
  %13 = icmp sge i64 %1, %12
  %14 = icmp slt i64 %2, 0
  %15 = or i1 %14, %13
  br i1 %15, label %25, label %16

16:                                               ; preds = %11
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %18 = load i64, ptr %17, align 8, !tbaa !52
  %19 = icmp slt i64 %2, %18
  br i1 %19, label %20, label %25

20:                                               ; preds = %16
  %21 = mul nsw i64 %12, %2
  %22 = getelementptr inbounds nuw %struct.Color, ptr %7, i64 %21
  %23 = getelementptr inbounds nuw %struct.Color, ptr %22, i64 %1
  %24 = load i32, ptr %23, align 1
  br label %25

25:                                               ; preds = %11, %16, %3, %5, %20
  %26 = phi i32 [ %24, %20 ], [ 0, %5 ], [ 0, %3 ], [ 0, %16 ], [ 0, %11 ]
  ret i32 %26
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(write, argmem: readwrite, inaccessiblemem: none) uwtable(sync)
define void @rasterize_interactive_page(ptr noundef readonly captures(address_is_null) %0, ptr noundef readonly captures(address_is_null) %1) local_unnamed_addr #7 {
  %3 = icmp ne ptr %0, null
  %4 = icmp ne ptr %1, null
  %5 = and i1 %3, %4
  br i1 %5, label %6, label %357

6:                                                ; preds = %2
  %7 = load i64, ptr %1, align 8, !tbaa !32
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %9 = load ptr, ptr %8, align 8, !tbaa !53
  %10 = icmp eq ptr %9, null
  br i1 %10, label %110, label %11

11:                                               ; preds = %6
  %12 = getelementptr inbounds nuw i8, ptr %1, i64 24
  %13 = load i64, ptr %12, align 8, !tbaa !36
  %14 = getelementptr inbounds nuw i8, ptr %1, i64 16
  %15 = load i64, ptr %14, align 8, !tbaa !35
  %16 = tail call i64 @llvm.smax.i64(i64 %15, i64 0)
  %17 = add i64 %7, -8
  %18 = load i64, ptr %0, align 8, !tbaa !49
  %19 = tail call i64 @llvm.smin.i64(i64 %17, i64 %18)
  %20 = add nsw i64 %15, %13
  %21 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %22 = load i64, ptr %21, align 8, !tbaa !52
  %23 = tail call i64 @llvm.smin.i64(i64 %20, i64 %22)
  %24 = icmp slt i64 %16, %23
  %25 = icmp sgt i64 %19, 8
  %26 = select i1 %24, i1 %25, i1 false
  br i1 %26, label %27, label %44

27:                                               ; preds = %11, %38
  %28 = phi i64 [ %39, %38 ], [ %16, %11 ]
  br label %29

29:                                               ; preds = %29, %27
  %30 = phi i64 [ 8, %27 ], [ %36, %29 ]
  %31 = load ptr, ptr %8, align 8, !tbaa !53
  %32 = load i64, ptr %0, align 8, !tbaa !49
  %33 = mul nsw i64 %32, %28
  %34 = getelementptr %struct.Color, ptr %31, i64 %33
  %35 = getelementptr %struct.Color, ptr %34, i64 %30
  store i32 -14409440, ptr %35, align 1
  %36 = add nuw nsw i64 %30, 1
  %37 = icmp eq i64 %36, %19
  br i1 %37, label %38, label %29, !llvm.loop !60

38:                                               ; preds = %29
  %39 = add nuw nsw i64 %28, 1
  %40 = icmp eq i64 %39, %23
  br i1 %40, label %41, label %27, !llvm.loop !61

41:                                               ; preds = %38
  %42 = load ptr, ptr %8, align 8, !tbaa !53
  %43 = icmp eq ptr %42, null
  br i1 %43, label %110, label %44

44:                                               ; preds = %11, %41
  %45 = getelementptr inbounds nuw i8, ptr %1, i64 40
  %46 = load i64, ptr %45, align 8, !tbaa !38
  %47 = getelementptr inbounds nuw i8, ptr %1, i64 32
  %48 = load i64, ptr %47, align 8, !tbaa !37
  %49 = tail call i64 @llvm.smax.i64(i64 %48, i64 0)
  %50 = load i64, ptr %0, align 8, !tbaa !49
  %51 = tail call i64 @llvm.smin.i64(i64 %17, i64 %50)
  %52 = add nsw i64 %48, %46
  %53 = load i64, ptr %21, align 8, !tbaa !52
  %54 = tail call i64 @llvm.smin.i64(i64 %52, i64 %53)
  %55 = icmp slt i64 %49, %54
  %56 = icmp sgt i64 %51, 8
  %57 = select i1 %55, i1 %56, i1 false
  br i1 %57, label %58, label %75

58:                                               ; preds = %44, %69
  %59 = phi i64 [ %70, %69 ], [ %49, %44 ]
  br label %60

60:                                               ; preds = %60, %58
  %61 = phi i64 [ 8, %58 ], [ %67, %60 ]
  %62 = load ptr, ptr %8, align 8, !tbaa !53
  %63 = load i64, ptr %0, align 8, !tbaa !49
  %64 = mul nsw i64 %63, %59
  %65 = getelementptr %struct.Color, ptr %62, i64 %64
  %66 = getelementptr %struct.Color, ptr %65, i64 %61
  store i32 -12369860, ptr %66, align 1
  %67 = add nuw nsw i64 %61, 1
  %68 = icmp eq i64 %67, %51
  br i1 %68, label %69, label %60, !llvm.loop !60

69:                                               ; preds = %60
  %70 = add nuw nsw i64 %59, 1
  %71 = icmp eq i64 %70, %54
  br i1 %71, label %72, label %58, !llvm.loop !61

72:                                               ; preds = %69
  %73 = load ptr, ptr %8, align 8, !tbaa !53
  %74 = icmp eq ptr %73, null
  br i1 %74, label %110, label %75

75:                                               ; preds = %44, %72
  %76 = getelementptr inbounds nuw i8, ptr %1, i64 56
  %77 = load i64, ptr %76, align 8, !tbaa !40
  %78 = getelementptr inbounds nuw i8, ptr %1, i64 48
  %79 = load i64, ptr %78, align 8, !tbaa !39
  %80 = tail call i64 @llvm.smax.i64(i64 %79, i64 0)
  %81 = load i64, ptr %0, align 8, !tbaa !49
  %82 = tail call i64 @llvm.smin.i64(i64 %17, i64 %81)
  %83 = add nsw i64 %79, %77
  %84 = load i64, ptr %21, align 8, !tbaa !52
  %85 = tail call i64 @llvm.smin.i64(i64 %83, i64 %84)
  %86 = icmp slt i64 %80, %85
  %87 = icmp sgt i64 %82, 8
  %88 = select i1 %86, i1 %87, i1 false
  br i1 %88, label %96, label %89

89:                                               ; preds = %75
  %90 = getelementptr inbounds nuw i8, ptr %1, i64 64
  %91 = getelementptr inbounds nuw i8, ptr %1, i64 80
  %92 = getelementptr inbounds nuw i8, ptr %1, i64 72
  %93 = load i64, ptr %90, align 8, !tbaa !41
  %94 = load i64, ptr %91, align 8, !tbaa !43
  %95 = load i64, ptr %92, align 8, !tbaa !42
  br label %126

96:                                               ; preds = %75, %107
  %97 = phi i64 [ %108, %107 ], [ %80, %75 ]
  br label %98

98:                                               ; preds = %98, %96
  %99 = phi i64 [ 8, %96 ], [ %105, %98 ]
  %100 = load ptr, ptr %8, align 8, !tbaa !53
  %101 = load i64, ptr %0, align 8, !tbaa !49
  %102 = mul nsw i64 %101, %97
  %103 = getelementptr %struct.Color, ptr %100, i64 %102
  %104 = getelementptr %struct.Color, ptr %103, i64 %99
  store i32 -69400, ptr %104, align 1
  %105 = add nuw nsw i64 %99, 1
  %106 = icmp eq i64 %105, %82
  br i1 %106, label %107, label %98, !llvm.loop !60

107:                                              ; preds = %98
  %108 = add nuw nsw i64 %97, 1
  %109 = icmp eq i64 %108, %85
  br i1 %109, label %117, label %96, !llvm.loop !61

110:                                              ; preds = %72, %41, %6
  %111 = getelementptr inbounds nuw i8, ptr %1, i64 64
  %112 = getelementptr inbounds nuw i8, ptr %1, i64 80
  %113 = getelementptr inbounds nuw i8, ptr %1, i64 72
  %114 = load i64, ptr %111, align 8, !tbaa !41
  %115 = load i64, ptr %112, align 8, !tbaa !43
  %116 = load i64, ptr %113, align 8, !tbaa !42
  br label %160

117:                                              ; preds = %107
  %118 = load ptr, ptr %8, align 8, !tbaa !53
  %119 = icmp eq ptr %118, null
  %120 = getelementptr inbounds nuw i8, ptr %1, i64 64
  %121 = getelementptr inbounds nuw i8, ptr %1, i64 80
  %122 = getelementptr inbounds nuw i8, ptr %1, i64 72
  %123 = load i64, ptr %120, align 8, !tbaa !41
  %124 = load i64, ptr %121, align 8, !tbaa !43
  %125 = load i64, ptr %122, align 8, !tbaa !42
  br i1 %119, label %160, label %126

126:                                              ; preds = %89, %117
  %127 = phi i64 [ %95, %89 ], [ %125, %117 ]
  %128 = phi i64 [ %94, %89 ], [ %124, %117 ]
  %129 = phi i64 [ %93, %89 ], [ %123, %117 ]
  %130 = phi ptr [ %92, %89 ], [ %122, %117 ]
  %131 = phi ptr [ %91, %89 ], [ %121, %117 ]
  %132 = phi ptr [ %90, %89 ], [ %120, %117 ]
  %133 = tail call i64 @llvm.smax.i64(i64 %129, i64 0)
  %134 = add i64 %128, 8
  %135 = load i64, ptr %0, align 8, !tbaa !49
  %136 = tail call i64 @llvm.smin.i64(i64 %134, i64 %135)
  %137 = add nsw i64 %129, %127
  %138 = load i64, ptr %21, align 8, !tbaa !52
  %139 = tail call i64 @llvm.smin.i64(i64 %137, i64 %138)
  %140 = icmp slt i64 %133, %139
  %141 = icmp sgt i64 %136, 8
  %142 = select i1 %140, i1 %141, i1 false
  br i1 %142, label %146, label %143

143:                                              ; preds = %126
  %144 = getelementptr inbounds nuw i8, ptr %1, i64 88
  %145 = load i64, ptr %144, align 8, !tbaa !44
  br label %174

146:                                              ; preds = %126, %157
  %147 = phi i64 [ %158, %157 ], [ %133, %126 ]
  br label %148

148:                                              ; preds = %148, %146
  %149 = phi i64 [ 8, %146 ], [ %155, %148 ]
  %150 = load ptr, ptr %8, align 8, !tbaa !53
  %151 = load i64, ptr %0, align 8, !tbaa !49
  %152 = mul nsw i64 %151, %147
  %153 = getelementptr %struct.Color, ptr %150, i64 %152
  %154 = getelementptr %struct.Color, ptr %153, i64 %149
  store i32 -723983, ptr %154, align 1
  %155 = add nuw nsw i64 %149, 1
  %156 = icmp eq i64 %155, %136
  br i1 %156, label %157, label %148, !llvm.loop !60

157:                                              ; preds = %148
  %158 = add nuw nsw i64 %147, 1
  %159 = icmp eq i64 %158, %139
  br i1 %159, label %166, label %146, !llvm.loop !61

160:                                              ; preds = %117, %110
  %161 = phi i64 [ %116, %110 ], [ %125, %117 ]
  %162 = phi i64 [ %115, %110 ], [ %124, %117 ]
  %163 = phi i64 [ %114, %110 ], [ %123, %117 ]
  %164 = getelementptr inbounds nuw i8, ptr %1, i64 88
  %165 = load i64, ptr %164, align 8, !tbaa !44
  br label %211

166:                                              ; preds = %157
  %167 = load ptr, ptr %8, align 8, !tbaa !53
  %168 = load i64, ptr %132, align 8, !tbaa !41
  %169 = load i64, ptr %131, align 8, !tbaa !43
  %170 = load i64, ptr %130, align 8, !tbaa !42
  %171 = icmp eq ptr %167, null
  %172 = getelementptr inbounds nuw i8, ptr %1, i64 88
  %173 = load i64, ptr %172, align 8, !tbaa !44
  br i1 %171, label %211, label %174

174:                                              ; preds = %143, %166
  %175 = phi i64 [ %145, %143 ], [ %173, %166 ]
  %176 = phi ptr [ %144, %143 ], [ %172, %166 ]
  %177 = phi i64 [ %129, %143 ], [ %168, %166 ]
  %178 = phi i64 [ %128, %143 ], [ %169, %166 ]
  %179 = phi i64 [ %127, %143 ], [ %170, %166 ]
  %180 = add nsw i64 %178, 8
  %181 = tail call i64 @llvm.smax.i64(i64 %180, i64 0)
  %182 = tail call i64 @llvm.smax.i64(i64 %177, i64 0)
  %183 = add i64 %180, %175
  %184 = load i64, ptr %0, align 8, !tbaa !49
  %185 = tail call i64 @llvm.smin.i64(i64 %183, i64 %184)
  %186 = add nsw i64 %177, %179
  %187 = load i64, ptr %21, align 8, !tbaa !52
  %188 = tail call i64 @llvm.smin.i64(i64 %186, i64 %187)
  %189 = icmp slt i64 %182, %188
  %190 = icmp slt i64 %181, %185
  %191 = select i1 %189, i1 %190, i1 false
  br i1 %191, label %192, label %211

192:                                              ; preds = %174, %203
  %193 = phi i64 [ %204, %203 ], [ %182, %174 ]
  br label %194

194:                                              ; preds = %194, %192
  %195 = phi i64 [ %181, %192 ], [ %201, %194 ]
  %196 = load ptr, ptr %8, align 8, !tbaa !53
  %197 = load i64, ptr %0, align 8, !tbaa !49
  %198 = mul nsw i64 %197, %193
  %199 = getelementptr %struct.Color, ptr %196, i64 %198
  %200 = getelementptr %struct.Color, ptr %199, i64 %195
  store i32 -1, ptr %200, align 1
  %201 = add nuw nsw i64 %195, 1
  %202 = icmp eq i64 %201, %185
  br i1 %202, label %203, label %194, !llvm.loop !60

203:                                              ; preds = %194
  %204 = add nuw nsw i64 %193, 1
  %205 = icmp eq i64 %204, %188
  br i1 %205, label %206, label %192, !llvm.loop !61

206:                                              ; preds = %203
  %207 = load i64, ptr %132, align 8, !tbaa !41
  %208 = load i64, ptr %131, align 8, !tbaa !43
  %209 = load i64, ptr %176, align 8, !tbaa !44
  %210 = load i64, ptr %130, align 8, !tbaa !42
  br label %211

211:                                              ; preds = %160, %206, %174, %166
  %212 = phi i64 [ %210, %206 ], [ %179, %174 ], [ %170, %166 ], [ %161, %160 ]
  %213 = phi i64 [ %209, %206 ], [ %175, %174 ], [ %173, %166 ], [ %165, %160 ]
  %214 = phi i64 [ %208, %206 ], [ %178, %174 ], [ %169, %166 ], [ %162, %160 ]
  %215 = phi i64 [ %207, %206 ], [ %177, %174 ], [ %168, %166 ], [ %163, %160 ]
  %216 = add nsw i64 %213, %214
  tail call void @fb_draw_border(ptr noundef nonnull %0, i64 noundef 8, i64 noundef %215, i64 noundef %216, i64 noundef %212, i64 noundef 1, i64 4292926682)
  %217 = getelementptr inbounds nuw i8, ptr %1, i64 96
  %218 = load ptr, ptr %8, align 8, !tbaa !53
  %219 = icmp eq ptr %218, null
  br i1 %219, label %302, label %220

220:                                              ; preds = %211
  %221 = getelementptr inbounds nuw i8, ptr %1, i64 104
  %222 = load i64, ptr %221, align 8, !tbaa !46
  %223 = load i64, ptr %217, align 8, !tbaa !45
  %224 = tail call i64 @llvm.smax.i64(i64 %223, i64 0)
  %225 = add i64 %7, -8
  %226 = load i64, ptr %0, align 8, !tbaa !49
  %227 = tail call i64 @llvm.smin.i64(i64 %225, i64 %226)
  %228 = add nsw i64 %223, %222
  %229 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %230 = load i64, ptr %229, align 8, !tbaa !52
  %231 = tail call i64 @llvm.smin.i64(i64 %228, i64 %230)
  %232 = icmp slt i64 %224, %231
  %233 = icmp sgt i64 %227, 8
  %234 = select i1 %232, i1 %233, i1 false
  br i1 %234, label %235, label %252

235:                                              ; preds = %220, %246
  %236 = phi i64 [ %247, %246 ], [ %224, %220 ]
  br label %237

237:                                              ; preds = %237, %235
  %238 = phi i64 [ 8, %235 ], [ %244, %237 ]
  %239 = load ptr, ptr %8, align 8, !tbaa !53
  %240 = load i64, ptr %0, align 8, !tbaa !49
  %241 = mul nsw i64 %240, %236
  %242 = getelementptr %struct.Color, ptr %239, i64 %241
  %243 = getelementptr %struct.Color, ptr %242, i64 %238
  store i32 -723983, ptr %243, align 1
  %244 = add nuw nsw i64 %238, 1
  %245 = icmp eq i64 %244, %227
  br i1 %245, label %246, label %237, !llvm.loop !60

246:                                              ; preds = %237
  %247 = add nuw nsw i64 %236, 1
  %248 = icmp eq i64 %247, %231
  br i1 %248, label %249, label %235, !llvm.loop !61

249:                                              ; preds = %246
  %250 = load ptr, ptr %8, align 8, !tbaa !53
  %251 = icmp eq ptr %250, null
  br i1 %251, label %302, label %252

252:                                              ; preds = %220, %249
  %253 = load i64, ptr %217, align 8, !tbaa !45
  %254 = tail call i64 @llvm.smax.i64(i64 %253, i64 -4)
  %255 = add nsw i64 %254, 4
  %256 = load i64, ptr %0, align 8, !tbaa !49
  %257 = add nsw i64 %253, 8
  %258 = load i64, ptr %229, align 8, !tbaa !52
  %259 = tail call i64 @llvm.smin.i64(i64 %257, i64 %258)
  %260 = icmp slt i64 %255, %259
  %261 = icmp sgt i64 %256, 2
  %262 = select i1 %260, i1 %261, i1 false
  br i1 %262, label %263, label %267

263:                                              ; preds = %252
  %264 = icmp eq i64 %256, 3
  %265 = icmp eq i64 %256, 4
  %266 = icmp eq i64 %256, 5
  br label %274

267:                                              ; preds = %252
  %268 = getelementptr inbounds nuw i8, ptr %1, i64 112
  %269 = getelementptr inbounds nuw i8, ptr %1, i64 120
  %270 = getelementptr inbounds nuw i8, ptr %1, i64 128
  %271 = load i64, ptr %268, align 8, !tbaa !47
  %272 = load i64, ptr %269, align 8, !tbaa !62
  %273 = load i64, ptr %270, align 8, !tbaa !63
  br label %318

274:                                              ; preds = %263, %299
  %275 = phi i64 [ %300, %299 ], [ %255, %263 ]
  %276 = load ptr, ptr %8, align 8, !tbaa !53
  %277 = load i64, ptr %0, align 8, !tbaa !49
  %278 = mul nsw i64 %277, %275
  %279 = getelementptr %struct.Color, ptr %276, i64 %278
  %280 = getelementptr i8, ptr %279, i64 8
  store i32 -16777216, ptr %280, align 1
  br i1 %264, label %299, label %281, !llvm.loop !60

281:                                              ; preds = %274
  %282 = load ptr, ptr %8, align 8, !tbaa !53
  %283 = load i64, ptr %0, align 8, !tbaa !49
  %284 = mul nsw i64 %283, %275
  %285 = getelementptr %struct.Color, ptr %282, i64 %284
  %286 = getelementptr i8, ptr %285, i64 12
  store i32 -16777216, ptr %286, align 1
  br i1 %265, label %299, label %287, !llvm.loop !60

287:                                              ; preds = %281
  %288 = load ptr, ptr %8, align 8, !tbaa !53
  %289 = load i64, ptr %0, align 8, !tbaa !49
  %290 = mul nsw i64 %289, %275
  %291 = getelementptr %struct.Color, ptr %288, i64 %290
  %292 = getelementptr i8, ptr %291, i64 16
  store i32 -16777216, ptr %292, align 1
  br i1 %266, label %299, label %293, !llvm.loop !60

293:                                              ; preds = %287
  %294 = load ptr, ptr %8, align 8, !tbaa !53
  %295 = load i64, ptr %0, align 8, !tbaa !49
  %296 = mul nsw i64 %295, %275
  %297 = getelementptr %struct.Color, ptr %294, i64 %296
  %298 = getelementptr i8, ptr %297, i64 20
  store i32 -16777216, ptr %298, align 1
  br label %299

299:                                              ; preds = %293, %287, %281, %274
  %300 = add nuw nsw i64 %275, 1
  %301 = icmp eq i64 %300, %259
  br i1 %301, label %309, label %274, !llvm.loop !61

302:                                              ; preds = %249, %211
  %303 = getelementptr inbounds nuw i8, ptr %1, i64 112
  %304 = getelementptr inbounds nuw i8, ptr %1, i64 120
  %305 = getelementptr inbounds nuw i8, ptr %1, i64 128
  %306 = load i64, ptr %303, align 8, !tbaa !47
  %307 = load i64, ptr %304, align 8, !tbaa !62
  %308 = load i64, ptr %305, align 8, !tbaa !63
  br label %353

309:                                              ; preds = %299
  %310 = load ptr, ptr %8, align 8, !tbaa !53
  %311 = icmp eq ptr %310, null
  %312 = getelementptr inbounds nuw i8, ptr %1, i64 112
  %313 = getelementptr inbounds nuw i8, ptr %1, i64 120
  %314 = getelementptr inbounds nuw i8, ptr %1, i64 128
  %315 = load i64, ptr %312, align 8, !tbaa !47
  %316 = load i64, ptr %313, align 8, !tbaa !62
  %317 = load i64, ptr %314, align 8, !tbaa !63
  br i1 %311, label %353, label %318

318:                                              ; preds = %267, %309
  %319 = phi i64 [ %273, %267 ], [ %317, %309 ]
  %320 = phi i64 [ %272, %267 ], [ %316, %309 ]
  %321 = phi i64 [ %271, %267 ], [ %315, %309 ]
  %322 = phi ptr [ %270, %267 ], [ %314, %309 ]
  %323 = phi ptr [ %269, %267 ], [ %313, %309 ]
  %324 = phi ptr [ %268, %267 ], [ %312, %309 ]
  %325 = tail call i64 @llvm.smax.i64(i64 %321, i64 0)
  %326 = add i64 %320, 8
  %327 = load i64, ptr %0, align 8, !tbaa !49
  %328 = tail call i64 @llvm.smin.i64(i64 %326, i64 %327)
  %329 = add nsw i64 %321, %319
  %330 = load i64, ptr %229, align 8, !tbaa !52
  %331 = tail call i64 @llvm.smin.i64(i64 %329, i64 %330)
  %332 = icmp slt i64 %325, %331
  %333 = icmp sgt i64 %328, 8
  %334 = select i1 %332, i1 %333, i1 false
  br i1 %334, label %335, label %353

335:                                              ; preds = %318, %346
  %336 = phi i64 [ %347, %346 ], [ %325, %318 ]
  br label %337

337:                                              ; preds = %337, %335
  %338 = phi i64 [ 8, %335 ], [ %344, %337 ]
  %339 = load ptr, ptr %8, align 8, !tbaa !53
  %340 = load i64, ptr %0, align 8, !tbaa !49
  %341 = mul nsw i64 %340, %336
  %342 = getelementptr %struct.Color, ptr %339, i64 %341
  %343 = getelementptr %struct.Color, ptr %342, i64 %338
  store i32 -1543398, ptr %343, align 1
  %344 = add nuw nsw i64 %338, 1
  %345 = icmp eq i64 %344, %328
  br i1 %345, label %346, label %337, !llvm.loop !60

346:                                              ; preds = %337
  %347 = add nuw nsw i64 %336, 1
  %348 = icmp eq i64 %347, %331
  br i1 %348, label %349, label %335, !llvm.loop !61

349:                                              ; preds = %346
  %350 = load i64, ptr %324, align 8, !tbaa !47
  %351 = load i64, ptr %323, align 8, !tbaa !62
  %352 = load i64, ptr %322, align 8, !tbaa !63
  br label %353

353:                                              ; preds = %302, %349, %309, %318
  %354 = phi i64 [ %352, %349 ], [ %317, %309 ], [ %319, %318 ], [ %308, %302 ]
  %355 = phi i64 [ %351, %349 ], [ %316, %309 ], [ %320, %318 ], [ %307, %302 ]
  %356 = phi i64 [ %350, %349 ], [ %315, %309 ], [ %321, %318 ], [ %306, %302 ]
  tail call void @fb_draw_border(ptr noundef nonnull %0, i64 noundef 8, i64 noundef %356, i64 noundef %355, i64 noundef %354, i64 noundef 2, i64 4280557856)
  br label %357

357:                                              ; preds = %2, %353
  ret void
}

; Function Attrs: nounwind ssp uwtable(sync)
define noundef zeroext i1 @fb_write_ppm(ptr noundef readonly captures(address_is_null) %0, ptr noundef %1) local_unnamed_addr #9 {
  %3 = icmp eq ptr %0, null
  br i1 %3, label %46, label %4

4:                                                ; preds = %2
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %6 = load ptr, ptr %5, align 8, !tbaa !53
  %7 = icmp ne ptr %6, null
  %8 = icmp ne ptr %1, null
  %9 = and i1 %8, %7
  br i1 %9, label %10, label %46

10:                                               ; preds = %4
  %11 = tail call ptr @"\01_fopen"(ptr noundef nonnull %1, ptr noundef nonnull @.str) #14
  %12 = icmp eq ptr %11, null
  br i1 %12, label %46, label %13

13:                                               ; preds = %10
  %14 = load i64, ptr %0, align 8, !tbaa !49
  %15 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %16 = load i64, ptr %15, align 8, !tbaa !52
  %17 = tail call i32 (ptr, ptr, ...) @fprintf(ptr noundef nonnull %11, ptr noundef nonnull @.str.1, i64 noundef %14, i64 noundef %16) #14
  %18 = load i64, ptr %0, align 8, !tbaa !49
  %19 = load i64, ptr %15, align 8, !tbaa !52
  %20 = mul nsw i64 %19, %18
  %21 = icmp sgt i64 %20, 0
  br i1 %21, label %24, label %22

22:                                               ; preds = %24, %13
  %23 = tail call i32 @fclose(ptr noundef nonnull %11)
  br label %46

24:                                               ; preds = %13, %24
  %25 = phi i64 [ %41, %24 ], [ 0, %13 ]
  %26 = load ptr, ptr %5, align 8, !tbaa !53
  %27 = getelementptr inbounds nuw %struct.Color, ptr %26, i64 %25
  %28 = load i8, ptr %27, align 1, !tbaa !64
  %29 = zext i8 %28 to i32
  %30 = tail call i32 @fputc(i32 noundef %29, ptr noundef nonnull %11)
  %31 = load ptr, ptr %5, align 8, !tbaa !53
  %32 = getelementptr inbounds nuw %struct.Color, ptr %31, i64 %25, i32 1
  %33 = load i8, ptr %32, align 1, !tbaa !66
  %34 = zext i8 %33 to i32
  %35 = tail call i32 @fputc(i32 noundef %34, ptr noundef nonnull %11)
  %36 = load ptr, ptr %5, align 8, !tbaa !53
  %37 = getelementptr inbounds nuw %struct.Color, ptr %36, i64 %25, i32 2
  %38 = load i8, ptr %37, align 1, !tbaa !67
  %39 = zext i8 %38 to i32
  %40 = tail call i32 @fputc(i32 noundef %39, ptr noundef nonnull %11)
  %41 = add nuw nsw i64 %25, 1
  %42 = load i64, ptr %0, align 8, !tbaa !49
  %43 = load i64, ptr %15, align 8, !tbaa !52
  %44 = mul nsw i64 %43, %42
  %45 = icmp slt i64 %41, %44
  br i1 %45, label %24, label %22, !llvm.loop !68

46:                                               ; preds = %22, %10, %2, %4
  %47 = phi i1 [ false, %4 ], [ false, %2 ], [ false, %10 ], [ true, %22 ]
  ret i1 %47
}

declare ptr @"\01_fopen"(ptr noundef, ptr noundef) local_unnamed_addr #10

; Function Attrs: nofree nounwind
declare noundef i32 @fprintf(ptr noundef captures(none), ptr noundef readonly captures(none), ...) local_unnamed_addr #11

; Function Attrs: nofree nounwind
declare noundef i32 @fputc(i32 noundef, ptr noundef captures(none)) local_unnamed_addr #11

; Function Attrs: nofree nounwind
declare noundef i32 @fclose(ptr noundef captures(none)) local_unnamed_addr #11

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.smax.i64(i64, i64) #12

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.smin.i64(i64, i64) #12

attributes #0 = { mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #1 = { mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #2 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #3 = { nounwind ssp memory(readwrite, argmem: none) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #4 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #5 = { mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #6 = { mustprogress nounwind ssp willreturn uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #7 = { nofree norecurse nosync nounwind ssp memory(write, argmem: readwrite, inaccessiblemem: none) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #8 = { mustprogress nofree norecurse nosync nounwind ssp willreturn memory(read, inaccessiblemem: none) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #9 = { nounwind ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #10 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #11 = { nofree nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #12 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #13 = { allocsize(0) }
attributes #14 = { nounwind }

!llvm.module.flags = !{!0, !1, !2, !3, !4}
!llvm.ident = !{!5}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 27, i32 0]}
!1 = !{i32 1, !"wchar_size", i32 4}
!2 = !{i32 8, !"PIC Level", i32 2}
!3 = !{i32 7, !"uwtable", i32 1}
!4 = !{i32 7, !"frame-pointer", i32 1}
!5 = !{!"Apple clang version 21.0.0 (clang-2100.3.34.2)"}
!6 = !{!7, !8, i64 8}
!7 = !{!"", !8, i64 0, !11, i64 8, !8, i64 24, !11, i64 32, !8, i64 48, !8, i64 56, !11, i64 64, !8, i64 80, !8, i64 88, !8, i64 96, !11, i64 104, !8, i64 120, !11, i64 128, !8, i64 144, !8, i64 152, !8, i64 160, !8, i64 168, !11, i64 176}
!8 = !{!"long long", !9, i64 0}
!9 = !{!"omnipotent char", !10, i64 0}
!10 = !{!"Simple C/C++ TBAA"}
!11 = !{!"", !8, i64 0, !8, i64 8}
!12 = !{!7, !8, i64 0}
!13 = !{!7, !8, i64 16}
!14 = !{!7, !8, i64 32}
!15 = !{!7, !8, i64 24}
!16 = !{!7, !8, i64 40}
!17 = !{!7, !8, i64 64}
!18 = !{!7, !8, i64 48}
!19 = !{!7, !8, i64 56}
!20 = !{!7, !8, i64 72}
!21 = !{!7, !8, i64 104}
!22 = !{!7, !8, i64 96}
!23 = !{!7, !8, i64 80}
!24 = !{!7, !8, i64 88}
!25 = !{!7, !8, i64 112}
!26 = !{!7, !8, i64 128}
!27 = !{!7, !8, i64 120}
!28 = !{!7, !8, i64 136}
!29 = !{!7, !8, i64 176}
!30 = !{!7, !8, i64 160}
!31 = !{!7, !8, i64 168}
!32 = !{!33, !8, i64 0}
!33 = !{!"", !8, i64 0, !8, i64 8, !8, i64 16, !8, i64 24, !8, i64 32, !8, i64 40, !8, i64 48, !8, i64 56, !8, i64 64, !8, i64 72, !8, i64 80, !8, i64 88, !8, i64 96, !8, i64 104, !8, i64 112, !8, i64 120, !8, i64 128}
!34 = !{!33, !8, i64 8}
!35 = !{!33, !8, i64 16}
!36 = !{!33, !8, i64 24}
!37 = !{!33, !8, i64 32}
!38 = !{!33, !8, i64 40}
!39 = !{!33, !8, i64 48}
!40 = !{!33, !8, i64 56}
!41 = !{!33, !8, i64 64}
!42 = !{!33, !8, i64 72}
!43 = !{!33, !8, i64 80}
!44 = !{!33, !8, i64 88}
!45 = !{!33, !8, i64 96}
!46 = !{!33, !8, i64 104}
!47 = !{!33, !8, i64 112}
!48 = !{!8, !8, i64 0}
!49 = !{!50, !8, i64 0}
!50 = !{!"", !8, i64 0, !8, i64 8, !51, i64 16}
!51 = !{!"any pointer", !9, i64 0}
!52 = !{!50, !8, i64 8}
!53 = !{!50, !51, i64 16}
!54 = distinct !{!54, !55, !56, !57}
!55 = !{!"llvm.loop.mustprogress"}
!56 = !{!"llvm.loop.isvectorized", i32 1}
!57 = !{!"llvm.loop.unroll.runtime.disable"}
!58 = distinct !{!58, !55, !56, !57}
!59 = distinct !{!59, !55, !57, !56}
!60 = distinct !{!60, !55}
!61 = distinct !{!61, !55}
!62 = !{!33, !8, i64 120}
!63 = !{!33, !8, i64 128}
!64 = !{!65, !9, i64 0}
!65 = !{!"", !9, i64 0, !9, i64 1, !9, i64 2, !9, i64 3}
!66 = !{!65, !9, i64 1}
!67 = !{!65, !9, i64 2}
!68 = distinct !{!68, !55}

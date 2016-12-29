//
//  ViewController.m
//  FFmpeg-pushStream
//
//  Created by LLQ on 16/12/23.
//  Copyright © 2016年 LLQ. All rights reserved.
//

#import "ViewController.h"
#include <libavformat/avformat.h>
#include <libavutil/mathematics.h>
#include <libavutil/time.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    
}

- (IBAction)startAction:(UIButton *)sender {
    
    char input_str_full[500] = {0};
    char output_str_full[500] = {0};
    
    //文件地址
    NSString *input_str = [[NSBundle mainBundle] pathForResource:@"war3end.mp4" ofType:nil];
    //推流地址
    NSString *output_str = @"rtmp://106.75.92.197/live/test";
    
    //将地址写入到创建好的容器
    sprintf(input_str_full, "%s",[input_str UTF8String]);
    sprintf(output_str_full, "%s",[output_str UTF8String]);
    
    NSLog(@"input_str_full:%s",input_str_full);
    NSLog(@"output_str_full:%s",output_str_full);
    
    //初始化
    AVOutputFormat *ofmt = NULL;
    //输入format和输出format
    AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx = NULL;
    AVPacket pkt;  //存储解码前数据
    char in_filename[500] = {0};
    char out_filename[500] = {0};
    int ret, i;
    int videoindex = -1;
    int frame_index = 0;
    int64_t start_time = 0;
    
    //strcpy(a,b) 把 b 中的内容复制到 a 中
    strcpy(in_filename, input_str_full);
    strcpy(out_filename, output_str_full);
    
    //注册
    av_register_all();
    //网络初始化
    avformat_network_init();
    
    //Input
    //打开文件，存储到输入上下文中
    if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
        printf("未能打开文件\n");
        goto end;
    }
    //查找输入流数据
    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        printf("未能找到输入流数据\n");
        goto end;
    }
    
    //输入流数据的数量循环
    for (i = 0; i < ifmt_ctx->nb_streams; i ++) {
        if (ifmt_ctx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoindex = i;
            break;
        }
    }
    
    //检查一些设置的参数有无问题
    av_dump_format(ifmt_ctx, 0, in_filename, 0);
    
    
    //Output
    //初始化输出上下文
    avformat_alloc_output_context2(&ofmt_ctx, NULL, "flv", out_filename); //RTMP
//    avformat_alloc_output_context2(&ofmt_ctx, NULL, "mpegts", out_filename); //UDP
    
    if (!ofmt_ctx) {
        printf("输出上下文未能初始化成功\n");
        ret = AVERROR_UNKNOWN;
        goto end;
    }
    
    //从输出上下文中拿到存储输出信息的结构体
    ofmt = ofmt_ctx->oformat;
    
    for (i = 0; i < ifmt_ctx->nb_streams; i ++) {
        
        //获取输入视频流
        AVStream *in_stream = ifmt_ctx->streams[i];
        //为输出上下文添加音视频流（初始化一个音视频流容器）
        AVStream *out_stream = avformat_new_stream(ofmt_ctx, in_stream->codec->codec);
        if (!out_stream) {
            printf("未能成功添加音视频流\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }
        
        //将输入编解码器上下文信息 copy 给输出编解码器上下文
        ret = avcodec_copy_context(out_stream->codec, in_stream->codec);
        if (ret < 0) {
            printf("copy 编解码器上下文失败\n");
            goto end;
        }
        
        //这里没看懂....
        out_stream->codec->codec_tag = 0;
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
            out_stream->codec->flags = out_stream->codec->flags | CODEC_FLAG_GLOBAL_HEADER;
        }
        
    }
    
    //检查参数设置有无问题
    av_dump_format(ofmt_ctx, 0, out_filename, 1);
    
    //打开输出地址（推流地址）
    if (!(ofmt->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, out_filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            printf("无法打开地址 '%s'",out_filename);
            goto end;
        }
    }
    
    //写视频文件头
    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        printf("在 URL 所在的文件写视频头出错\n");
        goto end;
    }
    
    //取得时间
    start_time = av_gettime();
    
    while (1) {
        //输入输出视频流
        AVStream *in_stream, *out_stream;
        //获取解码前数据
        ret = av_read_frame(ifmt_ctx, &pkt);
        if (ret < 0) {
            break;
        }
        
        /*
         PTS（Presentation Time Stamp）显示播放时间
         DTS（Decoding Time Stamp）解码时间
         */
        //没有显示时间（比如未解码的 H.264 ）
        if (pkt.pts == AV_NOPTS_VALUE) {
            //AVRational time_base：时基。通过该值可以把PTS，DTS转化为真正的时间。
            AVRational time_base1 = ifmt_ctx->streams[videoindex]->time_base;
            
            //计算两帧之间的时间
            /*
             r_frame_rate 基流帧速率  （不是太懂）
             av_q2d 转化为double类型
             */
            int64_t calc_duration = (double)AV_TIME_BASE/av_q2d(ifmt_ctx->streams[videoindex]->r_frame_rate);
            
            //配置参数
            pkt.pts = (double)(frame_index*calc_duration)/(double)(av_q2d(time_base1)*AV_TIME_BASE);
            pkt.dts = pkt.pts;
            pkt.duration = (double)calc_duration/(double)(av_q2d(time_base1)*AV_TIME_BASE);
        }
        
        //延时
        if (pkt.stream_index == videoindex) {
            AVRational time_base = ifmt_ctx->streams[videoindex]->time_base;
            AVRational time_base_q = {1,AV_TIME_BASE};
            //计算视频播放时间
            int64_t pts_time = av_rescale_q(pkt.dts, time_base, time_base_q);
            //计算实际视频的播放时间
            int64_t now_time = av_gettime() - start_time;
            if (pts_time > now_time) {
                //睡眠一段时间（目的是让当前视频记录的播放时间与实际时间同步）
                av_usleep((unsigned int)(pts_time - now_time));
            }
        }
        
        in_stream = ifmt_ctx->streams[pkt.stream_index];
        out_stream = ofmt_ctx->streams[pkt.stream_index];
        
        //计算延时后，重新指定时间戳
        pkt.pts = av_rescale_q_rnd(pkt.pts, in_stream->time_base, out_stream->time_base, (AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
        pkt.dts = av_rescale_q_rnd(pkt.dts, in_stream->time_base, out_stream->time_base, (AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
        pkt.duration = (int)av_rescale_q(pkt.duration, in_stream->time_base, out_stream->time_base);
        //字节流的位置，-1 表示不知道字节流位置
        pkt.pos = -1;
        
        if (pkt.stream_index == videoindex) {
            printf("Send %8d video frames to output URL\n",frame_index);
            frame_index++;
        }
        
        //向输出上下文发送（向地址推送）
        ret = av_interleaved_write_frame(ofmt_ctx, &pkt);
        
        if (ret < 0) {
            printf("发送数据包出错\n");
            break;
        }
        
        //释放
        av_free_packet(&pkt);
        
    }
    
    //写文件尾
    av_write_trailer(ofmt_ctx);
    
    
    //end 节点
end:
    
    //关闭输入上下文
    avformat_close_input(&ifmt_ctx);
    //关闭输出上下文
    if (ofmt_ctx && !(ofmt->flags & AVFMT_NOFILE)) {
        avio_close(ofmt_ctx->pb);
    }
    //释放输出上下文
    avformat_free_context(ofmt_ctx);
    if (ret < 0 && ret != AVERROR_EOF) {
        printf("发生错误\n");
        return;
    }
    return;
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end

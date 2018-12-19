//
//  ViewController.m
//  TraceAllMsgDemo
//
//  Created by everettjf on 21/09/2017.
//  Copyright © 2017 everettjf. All rights reserved.
//

#import "ViewController.h"


@interface ViewController ()

@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self hello];
    
}

- (void)hello{
    
    sleep(200);
    [self world];
}

- (void)world{
    
    sleep(100);
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end

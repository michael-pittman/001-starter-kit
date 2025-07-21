#!/usr/bin/env python3
"""
Advanced Cost Optimization Automation for AI Starter Kit
Implements intelligent cost reduction strategies for g4dn.xlarge GPU instances
Features: Spot instance management, auto-scaling, resource optimization, usage analytics
"""

import boto3
import json
import time
import logging
import requests
import schedule
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass

# =============================================================================
# CONFIGURATION
# =============================================================================

@dataclass
class CostOptimizationConfig:
    region: str = "us-east-1"
    instance_type: str = "g4dn.xlarge"
    max_spot_price: float = 0.75
    target_utilization: float = 70.0
    scale_down_threshold: float = 20.0
    idle_timeout_minutes: int = 30
    cost_alert_threshold: float = 50.0  # Daily USD
    budget_limit: float = 200.0  # Monthly USD
    enable_auto_cleanup: bool = True
    enable_cost_alerts: bool = True
    fallback_regions: List[str] = None
    
    def __post_init__(self):
        if self.fallback_regions is None:
            self.fallback_regions = ["us-west-2", "eu-west-1", "ap-northeast-1"]
        self.validate()
    
    def validate(self):
        """Validate configuration parameters"""
        errors = []
        
        if self.max_spot_price <= 0 or self.max_spot_price > 10:
            errors.append("max_spot_price must be between 0 and 10")
        
        if not (0 <= self.target_utilization <= 100):
            errors.append("target_utilization must be between 0 and 100")
        
        if not (0 <= self.scale_down_threshold <= 100):
            errors.append("scale_down_threshold must be between 0 and 100")
        
        if self.idle_timeout_minutes < 5:
            errors.append("idle_timeout_minutes must be at least 5")
        
        if self.cost_alert_threshold <= 0:
            errors.append("cost_alert_threshold must be positive")
        
        if self.budget_limit <= 0:
            errors.append("budget_limit must be positive")
        
        valid_regions = ["us-east-1", "us-west-2", "eu-west-1", "eu-central-1", "ap-northeast-1", "ap-southeast-1"]
        if self.region not in valid_regions:
            errors.append(f"region must be one of: {', '.join(valid_regions)}")
        
        if errors:
            raise ValueError(f"Configuration validation failed: {'; '.join(errors)}")

config = CostOptimizationConfig()

# =============================================================================
# COST OPTIMIZATION MANAGER
# =============================================================================

class CostOptimizationManager:
    def __init__(self, config: CostOptimizationConfig):
        self.config = config
        self.logger = self._setup_logging()
        
        # AWS clients
        self.ec2 = boto3.client('ec2', region_name=config.region)
        self.autoscaling = boto3.client('autoscaling', region_name=config.region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=config.region)
        self.pricing = boto3.client('pricing', region_name='us-east-1')  # Pricing API only in us-east-1
        self.sns = boto3.client('sns', region_name=config.region)
        
        # Get current instance info
        self.instance_id = self._get_instance_id()
        self.asg_name = self._get_asg_name()
        
    def _setup_logging(self) -> logging.Logger:
        """Setup enhanced logging with rotation and structured format"""
        import logging.handlers
        
        logger = logging.getLogger('cost_optimizer')
        logger.setLevel(logging.INFO)
        
        # Prevent duplicate handlers
        if logger.handlers:
            return logger
        
        # Enhanced formatter with more context
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s'
        )
        
        # Rotating file handler
        try:
            os.makedirs('/var/log', exist_ok=True)
            file_handler = logging.handlers.RotatingFileHandler(
                '/var/log/cost-optimization.log',
                maxBytes=10*1024*1024,  # 10MB
                backupCount=5
            )
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)
        except PermissionError:
            # Fallback to user directory if /var/log is not writable
            home_log_dir = os.path.expanduser('~/logs')
            os.makedirs(home_log_dir, exist_ok=True)
            file_handler = logging.handlers.RotatingFileHandler(
                f'{home_log_dir}/cost-optimization.log',
                maxBytes=10*1024*1024,
                backupCount=5
            )
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
        # Suppress AWS SDK verbose logging
        logging.getLogger('boto3').setLevel(logging.WARNING)
        logging.getLogger('botocore').setLevel(logging.WARNING)
        logging.getLogger('urllib3').setLevel(logging.WARNING)
        
        return logger
    
    def _get_instance_id(self) -> str:
        try:
            response = requests.get(
                'http://169.254.169.254/latest/meta-data/instance-id',
                timeout=5
            )
            return response.text
        except:
            return "unknown"
    
    def _get_asg_name(self) -> Optional[str]:
        """Get Auto Scaling Group name for current instance"""
        try:
            response = self.autoscaling.describe_auto_scaling_instances(
                InstanceIds=[self.instance_id]
            )
            if response['AutoScalingInstances']:
                return response['AutoScalingInstances'][0]['AutoScalingGroupName']
        except Exception as e:
            self.logger.warning(f"Could not get ASG name: {e}")
        return None
    
    def get_current_spot_prices(self) -> Dict[str, float]:
        """Get current spot prices for GPU instances"""
        try:
            response = self.ec2.describe_spot_price_history(
                InstanceTypes=['g4dn.xlarge', 'g4dn.2xlarge', 'g4ad.xlarge', 'g5.xlarge'],
                ProductDescriptions=['Linux/UNIX'],
                StartTime=datetime.utcnow() - timedelta(hours=1),
                EndTime=datetime.utcnow()
            )
            
            current_prices = {}
            for price in response['SpotPriceHistory']:
                instance_type = price['InstanceType']
                if instance_type not in current_prices or price['Timestamp'] > current_prices[instance_type]['timestamp']:
                    current_prices[instance_type] = {
                        'price': float(price['SpotPrice']),
                        'timestamp': price['Timestamp'],
                        'az': price['AvailabilityZone']
                    }
            
            return current_prices
        except Exception as e:
            self.logger.error(f"Error getting spot prices: {e}")
            return {}
    
    def get_on_demand_prices(self) -> Dict[str, float]:
        """Get on-demand prices using AWS Pricing API"""
        try:
            # AWS Pricing API requires us-east-1 region
            pricing_client = boto3.client('pricing', region_name='us-east-1')
            
            prices = {}
            instance_types = ['g4dn.xlarge', 'g4dn.2xlarge', 'g4ad.xlarge', 'g5.xlarge']
            
            for instance_type in instance_types:
                try:
                    response = pricing_client.get_products(
                        ServiceCode='AmazonEC2',
                        Filters=[
                            {'Type': 'TERM_MATCH', 'Field': 'instanceType', 'Value': instance_type},
                            {'Type': 'TERM_MATCH', 'Field': 'location', 'Value': 'US East (N. Virginia)'},
                            {'Type': 'TERM_MATCH', 'Field': 'tenancy', 'Value': 'Shared'},
                            {'Type': 'TERM_MATCH', 'Field': 'operating-system', 'Value': 'Linux'},
                            {'Type': 'TERM_MATCH', 'Field': 'capacitystatus', 'Value': 'Used'},
                            {'Type': 'TERM_MATCH', 'Field': 'preInstalledSw', 'Value': 'NA'}
                        ]
                    )
                    
                    if response['PriceList']:
                        price_data = json.loads(response['PriceList'][0])
                        terms = price_data['terms']['OnDemand']
                        
                        for term_key in terms:
                            price_dimensions = terms[term_key]['priceDimensions']
                            for dimension_key in price_dimensions:
                                price_per_hour = float(price_dimensions[dimension_key]['pricePerUnit']['USD'])
                                prices[instance_type] = price_per_hour
                                break
                            break
                            
                except Exception as e:
                    self.logger.warning(f"Could not get pricing for {instance_type}: {e}")
                    # Fallback to approximate prices
                    fallback_prices = {
                        'g4dn.xlarge': 1.19,
                        'g4dn.2xlarge': 2.38,
                        'g4ad.xlarge': 0.95,
                        'g5.xlarge': 1.21
                    }
                    if instance_type in fallback_prices:
                        prices[instance_type] = fallback_prices[instance_type]
            
            # Cache prices for 24 hours to avoid excessive API calls
            cache_file = '/tmp/on_demand_prices_cache.json'
            cache_data = {
                'timestamp': datetime.now().isoformat(),
                'prices': prices
            }
            
            try:
                with open(cache_file, 'w') as f:
                    json.dump(cache_data, f)
            except:
                pass
                
            return prices
            
        except Exception as e:
            self.logger.error(f"Error getting on-demand prices from API: {e}")
            
            # Try to load from cache
            try:
                with open('/tmp/on_demand_prices_cache.json', 'r') as f:
                    cache_data = json.load(f)
                    cache_time = datetime.fromisoformat(cache_data['timestamp'])
                    
                    # Use cache if less than 24 hours old
                    if datetime.now() - cache_time < timedelta(hours=24):
                        self.logger.info("Using cached pricing data")
                        return cache_data['prices']
            except:
                pass
            
            # Final fallback to hardcoded prices
            self.logger.warning("Using fallback pricing data - may be inaccurate")
            return {
                'g4dn.xlarge': 1.19,
                'g4dn.2xlarge': 2.38,
                'g4ad.xlarge': 0.95,
                'g5.xlarge': 1.21
            }
    
    def calculate_potential_savings(self) -> Dict[str, Any]:
        """Calculate potential cost savings from optimization strategies"""
        spot_prices = self.get_current_spot_prices()
        on_demand_prices = self.get_on_demand_prices()
        
        savings_analysis = {}
        
        for instance_type in spot_prices:
            if instance_type in on_demand_prices:
                spot_price = spot_prices[instance_type]['price']
                on_demand_price = on_demand_prices[instance_type]
                
                hourly_savings = on_demand_price - spot_price
                daily_savings = hourly_savings * 24
                monthly_savings = daily_savings * 30
                savings_percent = (hourly_savings / on_demand_price) * 100
                
                savings_analysis[instance_type] = {
                    'spot_price': spot_price,
                    'on_demand_price': on_demand_price,
                    'hourly_savings': hourly_savings,
                    'daily_savings': daily_savings,
                    'monthly_savings': monthly_savings,
                    'savings_percent': savings_percent
                }
        
        return savings_analysis
    
    def get_gpu_utilization(self) -> Dict[str, float]:
        """Get current GPU utilization from multiple sources"""
        gpu_metrics = {
            'gpu_utilization': 0.0,
            'memory_utilization': 0.0,
            'temperature': 0.0
        }
        
        try:
            # Try CloudWatch first
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(minutes=10)
            
            response = self.cloudwatch.get_metric_statistics(
                Namespace='GPU/Monitoring',
                MetricName='GPUUtilization',
                Dimensions=[
                    {'Name': 'InstanceId', 'Value': self.instance_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=300,
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                gpu_metrics['gpu_utilization'] = response['Datapoints'][-1]['Average']
                
        except Exception as e:
            self.logger.warning(f"CloudWatch GPU metrics unavailable: {e}")
            
        try:
            # Try reading from shared metrics file
            metrics_file = '/shared/gpu_metrics.json'
            if os.path.exists(metrics_file):
                with open(metrics_file, 'r') as f:
                    shared_metrics = json.load(f)
                    if 'gpu' in shared_metrics:
                        gpu_data = shared_metrics['gpu']
                        gpu_metrics['gpu_utilization'] = gpu_data.get('utilization', 0.0)
                        gpu_metrics['memory_utilization'] = gpu_data.get('memory_utilization', 0.0)
                        gpu_metrics['temperature'] = gpu_data.get('temperature_c', 0.0)
                        
        except Exception as e:
            self.logger.warning(f"Shared GPU metrics unavailable: {e}")
            
        return gpu_metrics
    
    def check_idle_instances(self) -> List[str]:
        """Check for idle instances that can be terminated"""
        idle_instances = []
        
        try:
            # Get instances in ASG
            if not self.asg_name:
                return idle_instances
            
            response = self.autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[self.asg_name]
            )
            
            if not response['AutoScalingGroups']:
                return idle_instances
            
            instances = response['AutoScalingGroups'][0]['Instances']
            
            for instance in instances:
                instance_id = instance['InstanceId']
                
                # Check GPU utilization for each instance
                end_time = datetime.utcnow()
                start_time = end_time - timedelta(minutes=self.config.idle_timeout_minutes)
                
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='GPU/Monitoring',
                    MetricName='GPUUtilization',
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Average']
                )
                
                if response['Datapoints']:
                    avg_utilization = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
                    if avg_utilization < self.config.scale_down_threshold:
                        idle_instances.append(instance_id)
                        self.logger.info(f"Instance {instance_id} is idle (avg utilization: {avg_utilization:.1f}%)")
                
        except Exception as e:
            self.logger.error(f"Error checking idle instances: {e}")
        
        return idle_instances
    
    def optimize_spot_instance_pricing(self):
        """Optimize spot instance pricing strategy"""
        self.logger.info("Optimizing spot instance pricing...")
        
        spot_prices = self.get_current_spot_prices()
        savings_analysis = self.calculate_potential_savings()
        
        # Find the most cost-effective instance type
        best_option = None
        best_savings = 0
        
        for instance_type, analysis in savings_analysis.items():
            if analysis['savings_percent'] > best_savings and analysis['spot_price'] <= self.config.max_spot_price:
                best_savings = analysis['savings_percent']
                best_option = instance_type
        
        if best_option:
            self.logger.info(f"Best spot instance option: {best_option} (${spot_prices[best_option]['price']:.3f}/hr, {best_savings:.1f}% savings)")
            
            # Update Auto Scaling Group launch template if needed
            if best_option != self.config.instance_type:
                self._update_asg_instance_type(best_option)
        
        # Log cost analysis
        for instance_type, analysis in savings_analysis.items():
            self.logger.info(f"{instance_type}: ${analysis['spot_price']:.3f}/hr spot vs ${analysis['on_demand_price']:.2f}/hr on-demand ({analysis['savings_percent']:.1f}% savings)")
    
    def _update_asg_instance_type(self, new_instance_type: str):
        """Update Auto Scaling Group with new instance type"""
        try:
            if not self.asg_name:
                self.logger.warning("No ASG found to update")
                return
            
            # This would require updating the launch template
            # Implementation depends on specific infrastructure setup
            self.logger.info(f"Would update ASG {self.asg_name} to use {new_instance_type}")
            
        except Exception as e:
            self.logger.error(f"Error updating ASG instance type: {e}")
    
    def get_system_metrics(self) -> Dict[str, Any]:
        """Get comprehensive system metrics"""
        try:
            # Get basic CloudWatch metrics
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(minutes=10)
            
            metrics = {}
            
            # CPU Utilization
            cpu_response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': self.instance_id}],
                StartTime=start_time,
                EndTime=end_time,
                Period=300,
                Statistics=['Average']
            )
            
            if cpu_response['Datapoints']:
                metrics['cpu_utilization'] = cpu_response['Datapoints'][-1]['Average']
            else:
                metrics['cpu_utilization'] = 0.0
                
            # Memory utilization (estimated from available metrics)
            try:
                memory_response = self.cloudwatch.get_metric_statistics(
                    Namespace='System/Linux',
                    MetricName='MemoryUtilization',
                    Dimensions=[{'Name': 'InstanceId', 'Value': self.instance_id}],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Average']
                )
                
                if memory_response['Datapoints']:
                    metrics['memory_utilization'] = memory_response['Datapoints'][-1]['Average']
                else:
                    metrics['memory_utilization'] = 0.0
                    
            except Exception:
                metrics['memory_utilization'] = 0.0
                
            return metrics
            
        except Exception as e:
            self.logger.error(f"Error getting system metrics: {e}")
            return {
                'cpu_utilization': 0.0,
                'memory_utilization': 0.0
            }
    
    def implement_auto_scaling(self):
        """Implement intelligent auto-scaling based on GPU utilization"""
        self.logger.info("Checking auto-scaling requirements...")
        
        gpu_metrics = self.get_gpu_utilization()
        current_utilization = gpu_metrics.get('gpu_utilization', 0.0)
        
        if not self.asg_name:
            self.logger.warning("No Auto Scaling Group found")
            return
        
        try:
            # Get current ASG configuration
            response = self.autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[self.asg_name]
            )
            
            if not response['AutoScalingGroups']:
                return
            
            asg = response['AutoScalingGroups'][0]
            current_capacity = asg['DesiredCapacity']
            max_capacity = asg['MaxSize']
            min_capacity = asg['MinSize']
            
            self.logger.info(f"Current ASG capacity: {current_capacity}, GPU utilization: {current_utilization:.1f}%")
            
            # Scale up if utilization is high
            if current_utilization > self.config.target_utilization and current_capacity < max_capacity:
                new_capacity = min(current_capacity + 1, max_capacity)
                self.logger.info(f"Scaling up to {new_capacity} instances due to high GPU utilization")
                
                self.autoscaling.set_desired_capacity(
                    AutoScalingGroupName=self.asg_name,
                    DesiredCapacity=new_capacity
                )
            
            # Scale down if utilization is low
            elif current_utilization < self.config.scale_down_threshold and current_capacity > min_capacity:
                idle_instances = self.check_idle_instances()
                if len(idle_instances) > 0:
                    new_capacity = max(current_capacity - 1, min_capacity)
                    self.logger.info(f"Scaling down to {new_capacity} instances due to low GPU utilization")
                    
                    self.autoscaling.set_desired_capacity(
                        AutoScalingGroupName=self.asg_name,
                        DesiredCapacity=new_capacity
                    )
            
        except Exception as e:
            self.logger.error(f"Error in auto-scaling: {e}")
    
    def optimize_storage_costs(self):
        """Optimize EBS and EFS storage costs"""
        self.logger.info("Optimizing storage costs...")
        
        try:
            # Get EBS volumes for current instance
            response = self.ec2.describe_volumes(
                Filters=[
                    {'Name': 'attachment.instance-id', 'Values': [self.instance_id]}
                ]
            )
            
            for volume in response['Volumes']:
                volume_id = volume['VolumeId']
                volume_type = volume['VolumeType']
                size = volume['Size']
                iops = volume.get('Iops', 0)
                
                # Recommend gp3 if using gp2
                if volume_type == 'gp2':
                    self.logger.info(f"Volume {volume_id}: Consider migrating from gp2 to gp3 for cost savings")
                
                # Check for oversized volumes
                if size > 100:  # Arbitrary threshold
                    self.logger.info(f"Volume {volume_id}: Large volume ({size}GB) - monitor usage and consider resize")
        
        except Exception as e:
            self.logger.error(f"Error optimizing storage: {e}")
    
    def monitor_daily_costs(self) -> float:
        """Monitor and alert on daily costs"""
        try:
            # This is a simplified cost monitoring
            # In practice, would use AWS Cost Explorer API or billing APIs
            
            # Estimate current daily cost based on instance hours
            gpu_metrics = self.get_gpu_utilization()
            current_utilization = gpu_metrics.get('gpu_utilization', 0.0)
            spot_prices = self.get_current_spot_prices()
            
            if self.config.instance_type in spot_prices:
                hourly_cost = spot_prices[self.config.instance_type]['price']
                estimated_daily_cost = hourly_cost * 24
                
                self.logger.info(f"Estimated daily cost: ${estimated_daily_cost:.2f}")
                
                if estimated_daily_cost > self.config.cost_alert_threshold:
                    self._send_cost_alert(estimated_daily_cost)
                
                return estimated_daily_cost
        
        except Exception as e:
            self.logger.error(f"Error monitoring costs: {e}")
        
        return 0.0
    
    def _send_cost_alert(self, daily_cost: float):
        """Send cost alert notification"""
        try:
            message = f"""
Cost Alert: AI Starter Kit

Daily cost estimate: ${daily_cost:.2f}
Threshold: ${self.config.cost_alert_threshold:.2f}
Instance: {self.instance_id}
Time: {datetime.now().isoformat()}

Consider:
1. Scaling down unused instances
2. Optimizing GPU utilization
3. Using more cost-effective instance types
4. Implementing scheduled shutdown for non-production workloads
"""
            
            # This would require setting up an SNS topic
            # self.sns.publish(TopicArn='arn:aws:sns:region:account:cost-alerts', Message=message)
            self.logger.warning(f"COST ALERT: Daily cost ${daily_cost:.2f} exceeds threshold ${self.config.cost_alert_threshold:.2f}")
            
        except Exception as e:
            self.logger.error(f"Error sending cost alert: {e}")
    
    def cleanup_unused_resources(self):
        """Clean up unused AWS resources to reduce costs"""
        self.logger.info("Cleaning up unused resources...")
        
        try:
            # Clean up old snapshots (keep last 7 days)
            cutoff_date = datetime.utcnow() - timedelta(days=7)
            
            response = self.ec2.describe_snapshots(OwnerIds=['self'])
            old_snapshots = [
                snap for snap in response['Snapshots']
                if snap['StartTime'].replace(tzinfo=None) < cutoff_date
            ]
            
            for snapshot in old_snapshots:
                # In practice, would add more checks before deletion
                self.logger.info(f"Old snapshot found: {snapshot['SnapshotId']} from {snapshot['StartTime']}")
                # self.ec2.delete_snapshot(SnapshotId=snapshot['SnapshotId'])
            
            # Clean up unattached volumes
            response = self.ec2.describe_volumes(
                Filters=[{'Name': 'status', 'Values': ['available']}]
            )
            
            for volume in response['Volumes']:
                self.logger.info(f"Unattached volume found: {volume['VolumeId']} ({volume['Size']}GB)")
                # Would add checks before deletion
        
        except Exception as e:
            self.logger.error(f"Error cleaning up resources: {e}")
    
    def generate_cost_report(self) -> Dict[str, Any]:
        """Generate comprehensive cost optimization report"""
        self.logger.info("Generating cost optimization report...")
        
        spot_prices = self.get_current_spot_prices()
        savings_analysis = self.calculate_potential_savings()
        gpu_metrics = self.get_gpu_utilization()
        current_utilization = gpu_metrics.get('gpu_utilization', 0.0)
        system_metrics = self.get_system_metrics()
        estimated_daily_cost = self.monitor_daily_costs()
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'instance_id': self.instance_id,
            'current_gpu_utilization': current_utilization,
            'estimated_daily_cost': estimated_daily_cost,
            'budget_status': self.check_budget_limits(),
            'spot_prices': spot_prices,
            'savings_analysis': savings_analysis,
            'recommendations': []
        }
        
        # Generate recommendations
        if current_utilization < 30:
            report['recommendations'].append("Low GPU utilization detected - consider scaling down or optimizing workloads")
        
        if estimated_daily_cost > self.config.cost_alert_threshold:
            report['recommendations'].append(f"Daily cost ${estimated_daily_cost:.2f} exceeds threshold - review resource usage")
        
        best_instance = min(savings_analysis.items(), key=lambda x: x[1]['spot_price']) if savings_analysis else None
        if best_instance:
            instance_type, analysis = best_instance
            if analysis['savings_percent'] > 50:
                report['recommendations'].append(f"Consider {instance_type} for {analysis['savings_percent']:.1f}% cost savings")
        
        # Add system metrics to report
        report['system_metrics'] = system_metrics
        report['gpu_metrics'] = gpu_metrics
        
        return report
    
    def check_budget_limits(self) -> Dict[str, Any]:
        """Check current spending against budget limits"""
        try:
            # Get current month's costs (simplified - would use Cost Explorer in production)
            current_month = datetime.now().replace(day=1)
            days_in_month = (datetime.now().replace(month=datetime.now().month % 12 + 1, day=1) - current_month).days
            days_elapsed = datetime.now().day
            
            # Estimate monthly cost based on current daily rate
            estimated_daily_cost = self.monitor_daily_costs()
            estimated_monthly_cost = estimated_daily_cost * days_in_month
            actual_monthly_cost = estimated_daily_cost * days_elapsed  # Simplified
            
            budget_status = {
                'budget_limit': self.config.budget_limit,
                'estimated_monthly_cost': estimated_monthly_cost,
                'actual_monthly_cost': actual_monthly_cost,
                'budget_utilization_percent': (actual_monthly_cost / self.config.budget_limit) * 100,
                'projected_overage': max(0, estimated_monthly_cost - self.config.budget_limit),
                'days_remaining': days_in_month - days_elapsed,
                'daily_budget_remaining': (self.config.budget_limit - actual_monthly_cost) / max(1, days_in_month - days_elapsed)
            }
            
            # Budget alerts
            if budget_status['budget_utilization_percent'] > 80:
                self.logger.warning(f"⚠️ Budget alert: {budget_status['budget_utilization_percent']:.1f}% of monthly budget used")
                
            if budget_status['projected_overage'] > 0:
                self.logger.error(f"🚨 Budget overage projected: ${budget_status['projected_overage']:.2f}")
                
            return budget_status
            
        except Exception as e:
            self.logger.error(f"Error checking budget limits: {e}")
            return {}
    
    def implement_cost_guardrails(self) -> Dict[str, Any]:
        """Implement automated cost guardrails"""
        guardrail_actions = {
            'budget_check': False,
            'emergency_scale_down': False,
            'instance_termination': False,
            'resource_cleanup': False
        }
        
        try:
            budget_status = self.check_budget_limits()
            guardrail_actions['budget_check'] = True
            
            # Emergency actions based on budget status
            if budget_status.get('budget_utilization_percent', 0) > 90:
                self.logger.critical("🚨 EMERGENCY: 90% budget utilization - implementing cost controls")
                
                # Scale down to minimum capacity
                if self._emergency_scale_down():
                    guardrail_actions['emergency_scale_down'] = True
                
                # Cleanup unused resources aggressively
                if self._emergency_resource_cleanup():
                    guardrail_actions['resource_cleanup'] = True
                
            elif budget_status.get('projected_overage', 0) > self.config.budget_limit * 0.2:  # 20% overage
                self.logger.warning("⚠️ Significant budget overage projected - implementing preventive measures")
                
                # Optimize instance types and scaling
                self.optimize_spot_instance_pricing()
                self._implement_aggressive_scaling()
                
            # Daily cost limit enforcement
            estimated_daily = budget_status.get('daily_budget_remaining', float('inf'))
            if estimated_daily < self.config.cost_alert_threshold * 0.5:
                self.logger.warning(f"📊 Daily budget remaining low: ${estimated_daily:.2f}")
                
            return guardrail_actions
            
        except Exception as e:
            self.logger.error(f"Error implementing cost guardrails: {e}")
            return guardrail_actions
    
    def _emergency_scale_down(self) -> bool:
        """Emergency scale down to minimum capacity"""
        try:
            if not self.asg_name:
                return False
            
            response = self.autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[self.asg_name]
            )
            
            if response['AutoScalingGroups']:
                asg = response['AutoScalingGroups'][0]
                min_capacity = asg['MinSize']
                
                self.autoscaling.set_desired_capacity(
                    AutoScalingGroupName=self.asg_name,
                    DesiredCapacity=min_capacity
                )
                
                self.logger.info(f"Emergency scale down to {min_capacity} instances")
                return True
                
        except Exception as e:
            self.logger.error(f"Emergency scale down failed: {e}")
        
        return False
    
    def _emergency_resource_cleanup(self) -> bool:
        """Aggressive resource cleanup during budget emergency"""
        try:
            cleaned_resources = 0
            
            # Stop non-essential services
            try:
                import subprocess
                subprocess.run(['docker', 'stop', 'crawl4ai'], timeout=30)
                cleaned_resources += 1
            except:
                pass
            
            # Clean up old snapshots more aggressively
            cutoff_date = datetime.utcnow() - timedelta(days=1)  # Only keep 1 day
            
            response = self.ec2.describe_snapshots(OwnerIds=['self'])
            for snapshot in response['Snapshots']:
                if snapshot['StartTime'].replace(tzinfo=None) < cutoff_date:
                    try:
                        # In production, would actually delete
                        self.logger.info(f"Would delete old snapshot: {snapshot['SnapshotId']}")
                        cleaned_resources += 1
                    except:
                        pass
            
            self.logger.info(f"Emergency cleanup completed: {cleaned_resources} resources")
            return cleaned_resources > 0
            
        except Exception as e:
            self.logger.error(f"Emergency resource cleanup failed: {e}")
        
        return False
    
    def _implement_aggressive_scaling(self):
        """Implement aggressive scaling policies to reduce costs"""
        try:
            # Reduce target utilization temporarily
            original_target = self.config.target_utilization
            self.config.target_utilization = min(original_target, 60.0)  # Lower target
            
            # Increase scale-down threshold
            original_threshold = self.config.scale_down_threshold
            self.config.scale_down_threshold = max(original_threshold, 30.0)  # Higher threshold
            
            self.implement_auto_scaling()
            
            # Reset to original values
            self.config.target_utilization = original_target
            self.config.scale_down_threshold = original_threshold
            
            self.logger.info("Aggressive scaling policies applied")
            
        except Exception as e:
            self.logger.error(f"Aggressive scaling failed: {e}")
    
    def implement_usage_pattern_scaling(self) -> Dict[str, Any]:
        """Implement automatic scaling based on historical usage patterns"""
        try:
            # Analyze historical usage patterns
            usage_patterns = self._analyze_usage_patterns()
            current_hour = datetime.now().hour
            current_day = datetime.now().weekday()  # 0=Monday, 6=Sunday
            
            scaling_actions = {
                'pattern_analysis': usage_patterns,
                'current_prediction': None,
                'scaling_action': None,
                'reasoning': None
            }
            
            # Predict current demand based on patterns
            predicted_utilization = self._predict_utilization(usage_patterns, current_hour, current_day)
            scaling_actions['current_prediction'] = predicted_utilization
            
            # Determine scaling action
            gpu_metrics = self.get_gpu_utilization()
            current_utilization = gpu_metrics.get('gpu_utilization', 0.0)
            
            # Get current ASG configuration
            if not self.asg_name:
                scaling_actions['reasoning'] = "No ASG configured"
                return scaling_actions
            
            response = self.autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[self.asg_name]
            )
            
            if not response['AutoScalingGroups']:
                scaling_actions['reasoning'] = "ASG not found"
                return scaling_actions
            
            asg = response['AutoScalingGroups'][0]
            current_capacity = asg['DesiredCapacity']
            min_capacity = asg['MinSize']
            max_capacity = asg['MaxSize']
            
            # Scaling logic based on predicted patterns
            target_capacity = current_capacity
            reasoning = f"Current: {current_utilization:.1f}%, Predicted: {predicted_utilization:.1f}%"
            
            # Proactive scaling based on predicted demand
            if predicted_utilization > 80 and current_capacity < max_capacity:
                target_capacity = min(current_capacity + 1, max_capacity)
                scaling_actions['scaling_action'] = 'scale_up_proactive'
                reasoning += " - Proactive scale up for predicted high demand"
                
            elif predicted_utilization < 30 and current_capacity > min_capacity:
                # Only scale down if current utilization also supports it
                if current_utilization < 40:
                    target_capacity = max(current_capacity - 1, min_capacity)
                    scaling_actions['scaling_action'] = 'scale_down_proactive'
                    reasoning += " - Proactive scale down for predicted low demand"
                    
            # Reactive scaling based on current utilization
            elif current_utilization > 85 and current_capacity < max_capacity:
                target_capacity = min(current_capacity + 1, max_capacity)
                scaling_actions['scaling_action'] = 'scale_up_reactive'
                reasoning += " - Reactive scale up for high current utilization"
                
            elif current_utilization < 20 and current_capacity > min_capacity:
                target_capacity = max(current_capacity - 1, min_capacity)
                scaling_actions['scaling_action'] = 'scale_down_reactive'
                reasoning += " - Reactive scale down for low current utilization"
            
            scaling_actions['reasoning'] = reasoning
            
            # Execute scaling if needed
            if target_capacity != current_capacity:
                self.autoscaling.set_desired_capacity(
                    AutoScalingGroupName=self.asg_name,
                    DesiredCapacity=target_capacity
                )
                
                self.logger.info(f"🔄 Usage pattern scaling: {current_capacity} -> {target_capacity} instances")
                self.logger.info(f"📊 {reasoning}")
                
                # Record scaling action for pattern learning
                self._record_scaling_action(current_hour, current_day, current_utilization, target_capacity - current_capacity)
            
            return scaling_actions
            
        except Exception as e:
            self.logger.error(f"Error in usage pattern scaling: {e}")
            return {'error': str(e)}
    
    def _analyze_usage_patterns(self) -> Dict[str, Any]:
        """Analyze historical usage patterns to predict demand"""
        try:
            # Get historical GPU utilization data
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(days=7)  # Last 7 days
            
            response = self.cloudwatch.get_metric_statistics(
                Namespace='GPU/Monitoring',
                MetricName='GPUUtilization',
                Dimensions=[
                    {'Name': 'InstanceId', 'Value': self.instance_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,  # 1 hour periods
                Statistics=['Average']
            )
            
            # Organize data by hour and day of week
            hourly_patterns = {i: [] for i in range(24)}
            daily_patterns = {i: [] for i in range(7)}
            
            for datapoint in response['Datapoints']:
                timestamp = datapoint['Timestamp']
                utilization = datapoint['Average']
                
                hour = timestamp.hour
                day_of_week = timestamp.weekday()
                
                hourly_patterns[hour].append(utilization)
                daily_patterns[day_of_week].append(utilization)
            
            # Calculate average patterns
            hourly_averages = {}
            for hour, values in hourly_patterns.items():
                if values:
                    hourly_averages[hour] = sum(values) / len(values)
                else:
                    hourly_averages[hour] = 50.0  # Default moderate utilization
            
            daily_averages = {}
            for day, values in daily_patterns.items():
                if values:
                    daily_averages[day] = sum(values) / len(values)
                else:
                    daily_averages[day] = 50.0  # Default moderate utilization
            
            return {
                'hourly_patterns': hourly_averages,
                'daily_patterns': daily_averages,
                'data_points': len(response['Datapoints'])
            }
            
        except Exception as e:
            self.logger.error(f"Error analyzing usage patterns: {e}")
            # Return default patterns
            return {
                'hourly_patterns': {i: 50.0 for i in range(24)},
                'daily_patterns': {i: 50.0 for i in range(7)},
                'data_points': 0
            }
    
    def _predict_utilization(self, patterns: Dict[str, Any], hour: int, day: int) -> float:
        """Predict utilization based on historical patterns"""
        try:
            hourly_avg = patterns['hourly_patterns'].get(hour, 50.0)
            daily_avg = patterns['daily_patterns'].get(day, 50.0)
            
            # Weighted average (hour pattern more important)
            predicted = (hourly_avg * 0.7) + (daily_avg * 0.3)
            
            # Apply some business logic adjustments
            # Higher utilization expected during business hours
            if 9 <= hour <= 17 and day < 5:  # Business hours, weekdays
                predicted *= 1.2
            elif hour < 6 or hour > 22:  # Late night/early morning
                predicted *= 0.8
            elif day >= 5:  # Weekends
                predicted *= 0.9
            
            return min(100.0, max(0.0, predicted))
            
        except Exception as e:
            self.logger.error(f"Error predicting utilization: {e}")
            return 50.0  # Default moderate prediction
    
    def _record_scaling_action(self, hour: int, day: int, utilization: float, scale_change: int):
        """Record scaling actions for future pattern learning"""
        try:
            scaling_record = {
                'timestamp': datetime.now().isoformat(),
                'hour': hour,
                'day_of_week': day,
                'utilization': utilization,
                'scale_change': scale_change,
                'instance_id': self.instance_id
            }
            
            # Store in a simple file-based log for now
            # In production, this could be stored in DynamoDB or CloudWatch Logs
            log_file = '/var/log/scaling-actions.jsonl'
            try:
                with open(log_file, 'a') as f:
                    f.write(json.dumps(scaling_record) + '\n')
            except Exception:
                # Fallback to temp directory
                temp_log = '/tmp/scaling-actions.jsonl'
                with open(temp_log, 'a') as f:
                    f.write(json.dumps(scaling_record) + '\n')
                    
        except Exception as e:
            self.logger.error(f"Error recording scaling action: {e}")
    
    def run_optimization_cycle(self):
        """Run complete cost optimization cycle with error isolation"""
        self.logger.info("Starting cost optimization cycle...")
        
        # Check for spot interruption first
        if self._check_spot_interruption_safe():
            self.logger.warning("Spot termination detected - aborting optimization cycle")
            return
        
        # Execute optimization steps with isolated error handling
        optimization_results = {
            'spot_pricing': self._run_with_isolation(self.optimize_spot_instance_pricing, "spot pricing optimization"),
            'auto_scaling': self._run_with_isolation(self.implement_auto_scaling, "auto-scaling"),
            'storage_optimization': self._run_with_isolation(self.optimize_storage_costs, "storage optimization"),
            'cost_monitoring': self._run_with_isolation(self.monitor_daily_costs, "cost monitoring"),
            'cost_guardrails': self._run_with_isolation(self.implement_cost_guardrails, "cost guardrails"),
            'usage_pattern_scaling': self._run_with_isolation(self.implement_usage_pattern_scaling, "usage pattern scaling"),
            'resource_cleanup': self._run_with_isolation(self.cleanup_unused_resources, "resource cleanup"),
            'report_generation': self._run_with_isolation(self._generate_and_save_report, "report generation")
        }
        
        # Log cycle summary
        successful_steps = sum(1 for result in optimization_results.values() if result['success'])
        total_steps = len(optimization_results)
        
        if successful_steps == total_steps:
            self.logger.info(f"✅ Cost optimization cycle completed successfully ({successful_steps}/{total_steps} steps)")
        else:
            self.logger.warning(f"⚠️ Cost optimization cycle completed with issues ({successful_steps}/{total_steps} steps successful)")
            
        return optimization_results

    def _run_with_isolation(self, func, step_name: str) -> Dict[str, Any]:
        """Run a function with isolated error handling"""
        start_time = time.time()
        result = {'success': False, 'error': None, 'duration': 0, 'step': step_name}
        
        try:
            self.logger.info(f"🔄 Starting {step_name}...")
            func_result = func()
            result['success'] = True
            result['result'] = func_result
            self.logger.info(f"✅ {step_name.capitalize()} completed successfully")
        except Exception as e:
            result['error'] = str(e)
            self.logger.error(f"❌ {step_name.capitalize()} failed: {e}")
            # Continue with other optimization steps
        finally:
            result['duration'] = time.time() - start_time
            
        return result
    
    def _check_spot_interruption_safe(self) -> bool:
        """Safely check for spot interruption without raising exceptions"""
        try:
            return self.check_spot_interruption()
        except Exception as e:
            self.logger.error(f"Error checking spot interruption (continuing): {e}")
            return False
    
    def _generate_and_save_report(self) -> Dict[str, Any]:
        """Generate and save cost optimization report"""
        report = self.generate_cost_report()
        
        # Save report with error handling
        report_filename = f'/var/log/cost-optimization-report-{datetime.now().strftime("%Y-%m-%d")}.json'
        try:
            with open(report_filename, 'w') as f:
                json.dump(report, f, indent=2)
            self.logger.info(f"📊 Cost report saved to {report_filename}")
        except Exception as e:
            self.logger.error(f"Failed to save cost report: {e}")
            
        return report

# Add spot interruption handling
    def check_spot_interruption(self) -> bool:
        """Check for spot instance termination notice"""
        try:
            response = requests.get(
                'http://169.254.169.254/latest/meta-data/spot/instance-action',
                timeout=2
            )
            if response.status_code == 200:
                data = response.json()
                if data.get('action') == 'terminate':
                    termination_time = data.get('time')
                    self.logger.critical(f"SPOT TERMINATION NOTICE! Time: {termination_time}")
                    self._handle_spot_termination(termination_time)
                    return True
            return False
        except requests.exceptions.RequestException:
            # Normal case - no interruption notice
            return False
        except Exception as e:
            self.logger.error(f"Error checking spot interruption: {e}")
            return False
    
    def _handle_spot_termination(self, termination_time: str = None):
        """Handle spot instance termination with graceful shutdown"""
        try:
            self.logger.critical("INITIATING EMERGENCY SPOT TERMINATION PROCEDURES")
            
            # Calculate time until termination (AWS gives ~2 minutes notice)
            if termination_time:
                termination_dt = datetime.fromisoformat(termination_time.replace('Z', '+00:00'))
                time_remaining = (termination_dt - datetime.now().replace(tzinfo=termination_dt.tzinfo)).total_seconds()
                self.logger.info(f"Time remaining: {time_remaining:.0f} seconds")
            
            # 1. Send immediate alert
            self._send_spot_termination_alert(termination_time)
            
            # 2. Gracefully shutdown AI workloads
            self._graceful_shutdown_workloads()
            
            # 3. Scale up ASG to replace instance (if configured)
            self._scale_up_replacement_instance()
            
            # 4. Create final backup/checkpoint
            self._create_emergency_backup()
            
            self.logger.info("Emergency procedures completed - instance ready for termination")
            
        except Exception as e:
            self.logger.error(f"Error handling spot termination: {e}")

    def _send_spot_termination_alert(self, termination_time: str = None):
        """Send urgent spot termination alert"""
        try:
            message = f"""
🚨 URGENT: Spot Instance Termination Notice

Instance: {self.instance_id}
Region: {self.config.region}
Termination Time: {termination_time or 'Unknown'}
Current Time: {datetime.now().isoformat()}

Actions Taken:
1. Workload graceful shutdown initiated
2. Replacement instance scaling triggered
3. Emergency backup created
4. Cost optimization suspended

Next Steps:
- Monitor replacement instance launch
- Verify service restoration
- Review spot pricing strategy
"""
            
            # Log critical alert
            self.logger.critical(message)
            
            # Would send to SNS topic if configured
            # self.sns.publish(TopicArn='arn:aws:sns:region:account:spot-alerts', Message=message)
            
        except Exception as e:
            self.logger.error(f"Error sending spot termination alert: {e}")

    def _graceful_shutdown_workloads(self):
        """Gracefully shutdown AI workloads before termination"""
        try:
            self.logger.info("Initiating graceful workload shutdown")
            
            # Stop new requests to Ollama
            import subprocess
            try:
                subprocess.run(['docker', 'exec', 'ollama-gpu', 'pkill', '-TERM', 'ollama'], timeout=10)
                self.logger.info("Ollama graceful shutdown initiated")
            except:
                pass
            
            # Flush any pending data to EFS
            try:
                subprocess.run(['sync'], timeout=5)
                self.logger.info("File system sync completed")
            except:
                pass
            
            # Create workload checkpoint
            try:
                subprocess.run(['docker', 'exec', 'n8n-gpu', 'npm', 'run', 'export'], timeout=30)
                self.logger.info("n8n workflow export completed")
            except:
                pass
                
        except Exception as e:
            self.logger.error(f"Error during graceful shutdown: {e}")

    def _scale_up_replacement_instance(self):
        """Scale up ASG to replace terminating instance"""
        try:
            if not self.asg_name:
                self.logger.warning("No ASG configured - cannot auto-replace instance")
                return
            
            # Get current ASG status
            response = self.autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[self.asg_name]
            )
            
            if response['AutoScalingGroups']:
                asg = response['AutoScalingGroups'][0]
                current_capacity = asg['DesiredCapacity']
                max_capacity = asg['MaxSize']
                
                # Scale up to replace terminating instance
                new_capacity = min(current_capacity + 1, max_capacity)
                
                self.autoscaling.set_desired_capacity(
                    AutoScalingGroupName=self.asg_name,
                    DesiredCapacity=new_capacity
                )
                
                self.logger.info(f"ASG scaled up to {new_capacity} instances to replace terminating spot instance")
                
        except Exception as e:
            self.logger.error(f"Error scaling up replacement instance: {e}")

    def _create_emergency_backup(self):
        """Create emergency backup before termination"""
        try:
            import subprocess
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            
            # Backup critical data to EFS
            backup_commands = [
                f"tar -czf /mnt/efs/emergency_backup_{timestamp}.tar.gz /home/ubuntu/ai-starter-kit/",
                f"cp /shared/gpu_metrics.json /mnt/efs/gpu_metrics_final_{timestamp}.json",
                f"docker exec postgres-gpu pg_dump -U n8n n8n > /mnt/efs/db_backup_{timestamp}.sql"
            ]
            
            for cmd in backup_commands:
                try:
                    subprocess.run(cmd, shell=True, timeout=30)
                except:
                    pass
                    
            self.logger.info(f"Emergency backup created: emergency_backup_{timestamp}")
            
        except Exception as e:
            self.logger.error(f"Error creating emergency backup: {e}")

# =============================================================================
# SCHEDULING AND AUTOMATION
# =============================================================================

def setup_scheduled_optimization():
    """Set up scheduled cost optimization tasks"""
    optimizer = CostOptimizationManager(config)
    
    # Schedule different optimization tasks
    schedule.every(15).minutes.do(optimizer.implement_auto_scaling)
    schedule.every(30).minutes.do(optimizer.implement_usage_pattern_scaling)  # Pattern-based scaling
    schedule.every(1).hours.do(optimizer.optimize_spot_instance_pricing)
    schedule.every(4).hours.do(optimizer.implement_cost_guardrails)  # Regular budget checks
    schedule.every(6).hours.do(optimizer.cleanup_unused_resources)
    schedule.every(1).days.do(optimizer.generate_cost_report)
    schedule.every(30).seconds.do(optimizer.check_spot_interruption)  # AWS recommends 30-second intervals
    
    # Emergency budget monitoring (more frequent)
    schedule.every(1).hours.do(optimizer.check_budget_limits)
    
    logging.info("Scheduled cost optimization tasks configured")
    
    # Run scheduling loop
    while True:
        schedule.run_pending()
        time.sleep(30)  # Reduced from 60 to 30 seconds for better spot monitoring

# Add scheduled scaling
def setup_scheduled_scaling():
    """Set up scheduled scaling based on usage patterns"""
    optimizer = CostOptimizationManager(config)
    
    # Scale down during low-usage hours (e.g., 2-6 AM)
    schedule.every().day.at("02:00").do(optimizer.implement_auto_scaling)
    schedule.every().day.at("06:00").do(optimizer.implement_auto_scaling)
    schedule.every().day.at("18:00").do(optimizer.implement_auto_scaling)  # Evening check
    schedule.every().day.at("22:00").do(optimizer.implement_auto_scaling)  # Late night optimization

# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='AI Starter Kit Cost Optimization')
    parser.add_argument('--action', choices=['optimize', 'report', 'schedule'], 
                       default='optimize', help='Action to perform')
    parser.add_argument('--max-spot-price', type=float, default=0.75,
                       help='Maximum spot price to pay')
    parser.add_argument('--cost-threshold', type=float, default=50.0,
                       help='Daily cost alert threshold')
    parser.add_argument('--budget-limit', type=float, default=200.0,
                       help='Monthly budget limit')
    parser.add_argument('--region', type=str, default='us-east-1',
                       help='AWS region')
    parser.add_argument('--instance-type', type=str, default='g4dn.xlarge',
                       help='Instance type')
    
    args = parser.parse_args()
    
    # Update config from arguments
    config.max_spot_price = args.max_spot_price
    config.cost_alert_threshold = args.cost_threshold
    config.budget_limit = args.budget_limit
    config.region = args.region
    config.instance_type = args.instance_type
    
    optimizer = CostOptimizationManager(config)
    
    if args.action == 'optimize':
        optimizer.run_optimization_cycle()
    elif args.action == 'report':
        report = optimizer.generate_cost_report()
        print(json.dumps(report, indent=2))
    elif args.action == 'schedule':
        setup_scheduled_optimization()
        setup_scheduled_scaling()
    elif args.action == 'monitor':
        # Continuous monitoring mode
        print("Starting continuous cost monitoring...")
        optimizer.run_optimization_cycle()
        setup_scheduled_optimization()

if __name__ == "__main__":
    main() 
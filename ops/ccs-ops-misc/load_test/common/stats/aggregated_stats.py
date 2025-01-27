"""Members of this file/module should be related to the collection of performance statistics during
a test run as well as the representation of those statistics via dataclasses or other suitable objects"""
from dataclasses import dataclass, fields
import time
from typing import Any, Dict, List, Optional, Union
from locust.stats import StatsEntry, sort_stats, PERCENTILES_TO_REPORT
from locust.env import Environment
from common.stats.stats_config import StatsEnvironment

ResponseTimePercentiles = Dict[str, Union[int, float]]
"""A type representing a dictionary of stringified percentile keys to their integer or floating-point
values"""


class StatsCollector(object):
    """Used to collect a snapshot of aggregated performance statistics of all tasks, or endpoints, that
    ran in the current Locust environment"""

    def __init__(self, locust_env: Environment, stats_tag: str, running_env: StatsEnvironment = StatsEnvironment.TEST) -> None:
        """Creates a new instance of StatsCollector given the current Locust environment and a list of percentiles to report.

        Args:
            locust_env (Environment): Current Locust environment
            stats_tag (str): A string which tags the output JSON; used to distinguish between separate test runs
            running_env (StatsEnvironment, optional): A StatsEnvironment enum which represents the current testing environment; either TEST or PROD. Defaults to TEST.
        """
        super().__init__()
        self.locust_env = locust_env

        self.stats_tag = stats_tag
        self.running_env = running_env

    def _get_task_stats_list(self) -> List['TaskStats']:
        """Returns a list of TaskStats representing the performance statistics of _all_ Locust tasks that ran

        Returns:
            List[TaskStats]: A List of TaskStats that represent the performance statistics of all Locust tasks
        """
        stats = self.locust_env.stats
        return [TaskStats.from_stats_entry(stats_entry) for stats_entry in sort_stats(stats.entries)]

    def collect_stats(self) -> 'AggregatedStats':
        """A method that returns an AggregatedStats instance representing a snapshot of the aggregated performance
        statistics of the current Locust environment at current time.

        Returns:
            AggregatedStats: An instance of AggregatedStats representing a snapshot of all stats at the current time
        """
        return AggregatedStats(metadata=StatsMetadata.from_locust_env(timestamp=int(time.time()), tag=self.stats_tag,
                                                                      environment=self.running_env, locust_env=self.locust_env),
                               tasks=self._get_task_stats_list())


@dataclass
class TaskStats():
    """Dataclass representing the performance statistics of a given Locust task"""
    task_name: str
    """The name specified by the task"""
    request_method: str
    """The HTTP request method (i.e. POST, GET) used by the Task"""
    num_requests: int
    """The total number of requests of this Task sent during the test run"""
    num_failures: int
    """The total number of failures received by this Task during the test run"""
    median_response_time: int
    """The median response time, in milliseconds, of each of this Task's requests"""
    average_response_time: float
    """The average response time, in milliseconds, of each of this Task's requests"""
    min_response_time: float
    """The fastest response time, in milliseconds, out of all this Task's requests"""
    max_response_time: float
    """The slowest respone time, in milliseconds, out of all this Task's requests"""
    total_reqs_per_second: float
    """The average number of requests-per-second of this Taks's requests over the test run"""
    total_fails_per_sec: float
    """The average number of failures-per-second of this Task's requests over the test run"""
    response_time_percentiles: ResponseTimePercentiles
    """A dictionary of response time percentiles indicating the percentage of requests that completed
    in a particular timeframe"""

    @classmethod
    def from_stats_entry(cls, stats_entry: StatsEntry) -> 'TaskStats':
        """A class method that constructs an instance of TaskStats from a Locust StatsEntry
        instance

        Args:
            stats_entry (StatsEntry): A Locust StatsEntry instance encapsulating a Task's stats

        Returns:
            TaskStats: A TaskStats dataclass instance that encapsulates the most important stats of a given Task
        """
        return cls(task_name=stats_entry.name, request_method=stats_entry.method,
                   num_requests=stats_entry.num_requests, num_failures=stats_entry.num_failures,
                   median_response_time=stats_entry.median_response_time, average_response_time=stats_entry.avg_response_time,
                   min_response_time=stats_entry.min_response_time or 0, max_response_time=stats_entry.max_response_time,
                   total_reqs_per_second=stats_entry.total_rps,
                   total_fails_per_sec=stats_entry.total_fail_per_sec,
                   response_time_percentiles=cls.__get_percentiles_dict(stats_entry))

    @classmethod
    def from_list(cls, values: List[Any]) -> 'TaskStats':
        """Constructs a new instance of TaskStats given a List of values in field declaration order.
        Used primarily to construct a TaskStats from Athena queries

        Args:
            values (List[Any]): A List of TaskStats values in field declaration order

        Returns:
            TaskStats: A TaskStats instance representing the values from the given List
        """
        # We assume the list is in field declaration order, otherwise we cannot
        # create a TaskStats from it
        inter_dict = {field.name: values[i]
                      for i, field in enumerate(fields(cls))}
        # response_time_percentiles will be a list as well, we need to convert it to a dict
        inter_dict['response_time_percentiles'] = {str(percentile): inter_dict['response_time_percentiles'][i]
                                                   for i, percentile in enumerate(PERCENTILES_TO_REPORT)}

        return TaskStats(**inter_dict)

    @classmethod
    def __get_percentiles_dict(cls, stats_entry: StatsEntry) -> ResponseTimePercentiles:
        """Returns a dictionary of response time percentiles indicating the percentage of requests that completed
        in a particular timeframe

        Args:
            stats_entry (StatsEntry): The Locust StatsEntry object which encodes a particular task's statistics

        Returns:
            Dict[str, int]: A dictionary of response time percentiles
        """
        if not stats_entry.num_requests:
            # If there were no requests made, simply return a dictionary with 0
            # for each of its values
            return {k: 0 for k in PERCENTILES_TO_REPORT}

        return {str(percentile): int(stats_entry.get_response_time_percentile(percentile) or 0)
                for percentile in PERCENTILES_TO_REPORT}


@dataclass
class StatsMetadata():
    """A dataclass encoding metadata that is necessary when comparing snapshots of aggregated performance stats"""
    timestamp: int
    """A timestamp indicating the time a stats snapshot was collected"""
    tag: str
    """The tag that partitions or buckets the statistics"""
    environment: StatsEnvironment
    """The environment that the stats were collected from"""
    stats_reset_after_spawn: bool
    """Indicates whether the test run's stats were reset after all users were spawned"""
    num_total_users: int
    """The number of users spawned running Tasks during the test run"""
    num_users_per_second: float
    """The number of users spawned per second when the test run started"""
    total_runtime: float
    """The total runtime of the test run"""

    @classmethod
    def from_locust_env(cls, timestamp: int, tag: str, environment: StatsEnvironment, locust_env: Environment) -> 'StatsMetadata':
        """A class method that constructs an instance of StatsMetadata by computing its fields from a given
        Locust environment

        Args:
            timestamp (int): A Unix timestamp indicating the time that the stats were collected
            tag (str): A simple string tag that is used as a partitioning tag
            environment (StatsEnvironment): The environment that the test run was started in
            locust_env (Environment): The current Locust environment

        Returns:
            StatsMetadata: A StatsMetadata instance encapsulating all of the necessary metadata to store and compare statistics
        """
        return cls(timestamp, tag, environment,
                   stats_reset_after_spawn=locust_env.reset_stats, num_total_users=locust_env.parsed_options.num_users,
                   num_users_per_second=locust_env.parsed_options.spawn_rate,
                   total_runtime=locust_env.stats.last_request_timestamp - locust_env.stats.start_time)


@dataclass
class AggregatedStats():
    """A dataclass encoding the entirety of performance statistics for every Locust Task along with
    metadata necessary for comparison and storage"""
    metadata: Optional[StatsMetadata]
    """An instance of StatsMetadata that encapsulates the necessary metadata about the set of Task statistics"""
    tasks: List[TaskStats]
    """A list of TaskStats where each entry represents the performance statistics of each Task"""

    def __post_init__(self):
        # Support conversion directly from a nested dictionary, such as when loading from JSON files
        # or from Athena
        try:
            self.metadata = StatsMetadata(**self.metadata)  # type: ignore
        except TypeError:
            pass
        
        try:
            self.tasks = [TaskStats(**task_dict) for task_dict in self.tasks]  # type: ignore
        except TypeError:
            pass

'''Ingest historical log data.'''
import sys

from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job
from awsglue.transforms import Unbox
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as SqlFuncs

args = getResolvedOptions(sys.argv, ["JOB_NAME"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

args = getResolvedOptions(sys.argv,
                          ['JOB_NAME',
                           'sourceDatabase',
                           'sourceTable',
                           'targetDatabase',
                           'targetTable'])

print("sourceDatabase is set to: ", args['sourceDatabase'])
print("   sourceTable is set to: ", args['sourceTable'])
print("targetDatabase is set to: ", args['targetDatabase'])
print("   targetTable is set to: ", args['targetTable'])

SourceDf = glueContext.create_dynamic_frame.from_catalog(
    database=args['sourceDatabase'],
    table_name=args['sourceTable'],
    transformation_ctx="SourceDf",
)

# With bookmarks enabled, we have to make sure that there is data to be processed
if SourceDf.count() > 0:
    print("here is the schema from the source")
    SourceDf.toDF().printSchema()

    NextNode = DynamicFrame.fromDF(
        Unbox.apply(frame = SourceDf, path = "message", format="json").toDF()
        .select(SqlFuncs.col("message.*")), glueContext, "nextNode")

    RelationalizeBeneNode = NextNode.relationalize(
        'root',
        's3://bfd-insights-bfd-577373831711/databases/bfd/temp/'
        ).select('root')

    print("here is the schema from the relationalize")
    RelationalizeBeneNode.toDF().printSchema()

    output = (
        RelationalizeBeneNode.toDF()
        .withColumn('year', SqlFuncs.substring('timestamp', 1,4))
        .withColumn('month', SqlFuncs.substring('timestamp', 6,2))
        .withColumn('day', SqlFuncs.substring('timestamp', 9,2))
        )

    OutputDy = DynamicFrame.fromDF(output, glueContext, "initializeNode")

    # Script generated for node Data Catalog table
    DataCatalogtable_node3 = glueContext.write_dynamic_frame.from_catalog(
        frame=OutputDy,
        database=args['targetDatabase'],
        table_name=args['targetTable'],
        additional_options={
            "enableUpdateCatalog": True,
            "updateBehavior": "UPDATE_IN_DATABASE",
            "partitionKeys": ["year", "month", "day"],
        },
        transformation_ctx="DataCatalogtable_node3",
    )

job.commit()

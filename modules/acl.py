import subprocess
import pandas as pd
import json

from loguru import logger
from pathlib import Path
from argparse import ArgumentParser

TABLE_COLUMNS = ['PRINCIPAL', 'HOST', 'RESOURCE-TYPE', 'RESOURCE-NAME', 'RESOURCE-PATTERN-TYPE', 'OPERATION', 'PERMISSION', 'ERROR']

def get_arguments():
    """Get arguments from command line"""
    parser = ArgumentParser("Module to create Redpanda ACLs")
    parser.add_argument(
        "acl_path",
        help=f"Path to JSON string containing the redpanda ACLs",
        type=str,
    )
    parser.add_argument(
        "kafka_broker",
        help=f"Redpanda broker to connect to",
        type=str,
    )
    parser.add_argument(
        "kafka_username",
        help=f"Kafka admin username",
        type=str,
    )
    parser.add_argument(
        "kafka_password_path",
        help=f"Path to Kafka admin password",
        type=str,
    )
    parser.add_argument(
        "--local",
        default=False,
        action="store_true",
        help=f"Disables authentication if used"
    )
    return parser.parse_args()

def create_acl(
        action: str,
        resource_type: str,
        resource_name: str,
        principal: str,
        operation: str,
        resource_pattern_type: str,
        broker: str,
        auth_command: list
    ):
    """Create ACLs in Redpanda"""

    if resource_type == 'TOPIC':
        resource = "--topic"
    elif resource_type == 'GROUP':
        resource = "--group"
    elif resource_type == 'TRANSACTIONAL_ID':
        resource = "--transactional-id"


    command = [
        "rpk",
        "acl",
        action,
        "--allow-principal",
        principal,
        "--operation",
        operation,
        "--resource-pattern-type",
        resource_pattern_type,
        "--brokers",
        broker ]
    if resource_type == 'CLUSTER':
        command.append("--cluster")
    else:
        command.extend([resource, resource_name])
    if action == 'delete':
        command.append("--no-confirm")

    total_command = command + auth_command

    subprocess.run(total_command)

def acl_to_df(acl_dict: str):
    """Convert ACLs from JSON to DataFrame"""

    acls = []
    for user in acl_dict:
        acl_list = acl_dict[user].get("acls")

        acl_row = {
            'PRINCIPAL': user,
            'HOST': '*',
            'PERMISSION': "ALLOW",
            'ERROR': "None"
        }
        for acl_def in acl_list:
            acl_row['RESOURCE-PATTERN-TYPE'] = acl_def["resource-pattern-type"].upper()

            for operation in acl_def["operation"]:
                acl_row['OPERATION'] = operation.upper()
                for group in acl_def["group"]:
                    acl_row['RESOURCE-TYPE'] = 'GROUP'
                    acl_row['RESOURCE-NAME'] = group
                    acls.append(acl_row.copy())

                for topic in acl_def["topic"]:
                    acl_row['RESOURCE-TYPE'] = 'TOPIC'
                    acl_row['RESOURCE-NAME'] = topic
                    acls.append(acl_row.copy())

                for transaction_id in acl_def["transactionalId"]:
                    acl_row['RESOURCE-TYPE'] = 'TRANSACTIONAL_ID'
                    acl_row['RESOURCE-NAME'] = transaction_id
                    acls.append(acl_row.copy())

                if acl_def["cluster"] == True:
                    acl_row['RESOURCE-TYPE'] = 'CLUSTER'
                    acl_row['RESOURCE-NAME'] = "kafka-cluster"
                    acls.append(acl_row.copy())

    acl_df = pd.DataFrame(acls)
    return acl_df

def list_acl(broker: str, auth_command: list):
    """List active ACLs in Redpanda"""

    command = [
        "rpk",
        "acl",
        "list",
        "--brokers",
        broker
    ]
    total_command = command + auth_command

    acl_list = subprocess.run(total_command, capture_output=True, check=True)

    output = acl_list.stdout.decode().strip().splitlines()[1:]
    data = []
    for output_row in output:
        new_data = output_row.split()
        new_data[0] = new_data[0].split(":")[1]
        if len(new_data) == 7:
            new_data.append("None")
        data.append(new_data)
    df = pd.DataFrame(data, columns=TABLE_COLUMNS)

    return df


def main():
    args = get_arguments()
    acl_path=args.acl_path
    broker = args.kafka_broker
    username = args.kafka_username
    password_path = args.kafka_password_path
    local = args.local

    with Path(acl_path).open("r") as f:
        acl_dict = json.load(f)

    password = Path(password_path).read_text()

    if not local:
        auth_command = ["--user", username, "--password", password]
    else:
        auth_command = []

    logger.info("Start creating ACLs")

    acl_df = acl_to_df(acl_dict)
    acl_list = list_acl(broker, auth_command)

    merge = acl_list.merge(acl_df, on=TABLE_COLUMNS,how='outer', indicator=True)
    new_acls = merge[merge['_merge'] == 'right_only']
    old_acls = merge[merge['_merge'] == 'left_only']

    logger.info(f"{len(new_acls)} ACLs to be created: \n {new_acls[TABLE_COLUMNS].to_string()}")

    for index, row in new_acls.iterrows():
        action = "create"
        create_acl(action, row['RESOURCE-TYPE'], row['RESOURCE-NAME'], row['PRINCIPAL'], row['OPERATION'], row['RESOURCE-PATTERN-TYPE'], broker, auth_command)


    logger.info(f"{len(old_acls)} ACLs to be deleted: \n {old_acls[TABLE_COLUMNS].to_string()}")

    for index, row in old_acls.iterrows():
        action = "delete"
        create_acl(action, row['RESOURCE-TYPE'], row['RESOURCE-NAME'], row['PRINCIPAL'], row['OPERATION'], row['RESOURCE-PATTERN-TYPE'], broker, auth_command)

    logger.info("Finished creating ACLs")

if __name__ == "__main__":
    main()


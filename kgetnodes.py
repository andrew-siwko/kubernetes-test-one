from kubernetes import client, config

def list_k8s_nodes():
    # Load configuration
    # Use config.load_kube_config() if running locally (e.g., ~/.kube/config)
    # Use config.load_incluster_config() if running inside a Pod
    try:
        config.load_kube_config()
    except:
        config.load_incluster_config()

    # Create an instance of the CoreV1Api
    v1 = client.CoreV1Api()

    # List all nodes
    node_list = v1.list_node()

    print(f"{'NODE NAME':<30} {'STATUS'}")
    print("-" * 40)

    for node in node_list.items:
        # Get the node name
        name = node.metadata.name
        
        # Determine node status
        # A node is "Ready" if the "Ready" condition status is True
        status = "Not Ready"
        for condition in node.status.conditions:
            if condition.type == "Ready" and condition.status == "True":
                status = "Ready"
                break
        
        print(f"{name:<30} {status}")


def get_k8s_node_list():
    return_node_list=[]
    # Load configuration
    # Use config.load_kube_config() if running locally (e.g., ~/.kube/config)
    # Use config.load_incluster_config() if running inside a Pod
    try:
        config.load_kube_config()
    except:
        config.load_incluster_config()

    # Create an instance of the CoreV1Api
    v1 = client.CoreV1Api()

    # List all nodes
    node_list = v1.list_node()


    for node in node_list.items:
        # Get the node name
        name = node.metadata.name
        
        # Determine node status
        # A node is "Ready" if the "Ready" condition status is True
        status = "Not Ready"
        for condition in node.status.conditions:
            if condition.type == "Ready" and condition.status == "True":
                status = "Ready"
                break

        print(f"{name:<30} {status}")
        
        return_node_list.append((name, status))

    return return_node_list


if __name__ == "__main__":
    list_k8s_nodes()
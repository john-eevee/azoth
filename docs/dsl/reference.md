# DSL Reference (Operators & Functions)

Athanor exposes several built-in Starlark functions via the `athanor_parser` (Rustler NIF).

## Workflows

### `workflow()`

The top-level container declaring an execution graph.

**Parameters**:
- `name` (string): The identifier of the workflow.
- `channels` (list): A list of channel definitions for incoming streams.
- `processes` (list): A list of evaluated process instances defining the dependency graph.

**Example**:
```python
workflow(
    name = "my_workflow",
    channels=[ channel_from_path("s3://bucket/*.csv") ],
    processes=[ ... ]
)
```

## Processes

### `process()`

Describes a unit of work to be executed on Quicksilver workers.

**Parameters**:
- `image` (string): Docker or OCI container image path.
- `command` (string): Execution command containing placeholders that resolve at runtime.
- `inputs` (dict): Named input channels mapping to `{key}`.
- `outputs` (dict | list): Named URI templates mapped to `{key}`, or glob patterns for dynamic outputs.
- `resources` (dict): Required resources (`cpu`, `mem`, `disk`).

### `Input(channel, format=None)`

Provides type/format safety for incoming channel data.

**Parameters**:
- `channel`: An existing channel or literal.
- `format` (optional string): Structural validation key (e.g. `format="bam"`).

### `Output(uri, format=None)`

Validates outgoing items written by a process.

**Parameters**:
- `uri` (string): The output template or glob string.
- `format` (optional string): Matches against connected input formats to validate graph structurally.

## Channels

### `channel_from_path(glob)`

Emits one `ArtifactRef` per path matching the glob. 

### `channel_literal(value)`

Injects a statically-known item or list as a one-time emit on a channel.

### `channel_zip(*channels)`

Synchronizes multiple channels, emitting an item only when all bound inputs have an item at the current read cursor.

### `channel_join(*channels)`

Waits for upstream processes to completely finish (and their output channels to close) before emitting the consolidated list of items.
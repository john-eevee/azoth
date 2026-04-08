# DSL Reference (KDL Nodes & Blocks)

Athanor uses KDL for workflow definitions, replacing the previous Starlark-based parser.

## Workflows

### `workflow`

The top-level container declaring an execution graph.

**Syntax**:
```kdl
workflow "name" {
    channel ...
    process ...
}
```

**Parameters**:
- `"name"` (string): The identifier of the workflow.

**Example**:
```kdl
workflow "my_workflow" {
    channel "data_stream" type="path" glob="s3://bucket/*.csv"
    process "my_process" { ... }
}
```

## Processes

### `process`

Describes a unit of work to be executed on Quicksilver workers.

**Syntax**:
```kdl
process "name" {
    image "..."
    command "..."
    inputs { ... }
    outputs { ... }
    resources { ... }
}
```

**Blocks**:
- `image` (string node): Docker or OCI container image path.
- `command` (string node): Execution command containing placeholders that resolve at runtime.
- `inputs` (block): Named input channels mapping to `{key}`.
- `outputs` (block): Named URI templates mapped to `{key}`, or glob patterns for dynamic outputs.
- `resources` (block): Required resources (`cpu`, `mem`, `disk`).

### `inputs` block

Provides type/format safety for incoming channel data and binds them to command placeholders.

**Syntax**:
```kdl
inputs {
    my_input channel="channel_name" format="bam"
}
```

**Properties**:
- `channel` (string): An existing channel name or `process_name.output_name`.
- `format` (optional string): Structural validation key (e.g. `format="bam"`).

### `outputs` block

Validates outgoing items written by a process and exposes them as channels to downstream processes.

**Syntax (Named Outputs)**:
```kdl
outputs {
    my_output "s3://bucket/{my_input.stem}.bam" format="bam"
}
```

**Syntax (Dynamic Globs)**:
```kdl
outputs {
    glob "./chunks/*.fa"
}
```

**Properties (for named outputs)**:
- Node value (string): The output template or glob string.
- `format` (optional string): Matches against connected input formats to validate graph structurally.

## Channels

Channels are defined using the `channel` node within a `workflow` block.

### `channel type="path"`

Emits one `ArtifactRef` per path matching the glob. 

**Syntax**:
```kdl
channel "name" type="path" glob="s3://bucket/*.csv"
```

### `channel type="literal"`

Injects a statically-known item or list as a one-time emit on a channel.

**Syntax**:
```kdl
channel "name" type="literal" value="s3://bucket/ref.fa"
```

### `channel type="zip"`

Synchronizes multiple channels, emitting an item only when all bound inputs have an item at the current read cursor.

**Syntax**:
```kdl
channel "name" type="zip" channels="channel1,channel2"
```

### `channel type="join"`

Waits for upstream processes to completely finish (and their output channels to close) before emitting the consolidated list of items.

**Syntax**:
```kdl
channel "name" type="join" channels="channel1"
```

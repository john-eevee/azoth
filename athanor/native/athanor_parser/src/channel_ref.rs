use allocative::Allocative;
use starlark::any::ProvidesStaticType;
use starlark::starlark_simple_value;
use starlark::values::{starlark_value, NoSerialize, StarlarkValue};
use std::fmt::{Display, Formatter};

#[derive(Debug, Clone, ProvidesStaticType, NoSerialize, Allocative)]
pub struct ChannelRef {
    pub id: String,
    pub format: String,
}

starlark_simple_value!(ChannelRef);

#[starlark_value(type = "Channel")]
impl<'v> StarlarkValue<'v> for ChannelRef {}

impl Display for ChannelRef {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "<Channel {} format={}>", self.id, self.format)
    }
}

#[derive(Debug, Clone, ProvidesStaticType, NoSerialize, Allocative)]
pub struct InputRef {
    pub channel: ChannelRef,
    pub format: String,
}

starlark_simple_value!(InputRef);

#[starlark_value(type = "Input")]
impl<'v> StarlarkValue<'v> for InputRef {}

impl Display for InputRef {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "<Input channel={} format={}>",
            self.channel.id, self.format
        )
    }
}

#[derive(Debug, Clone, ProvidesStaticType, NoSerialize, Allocative)]
pub struct OutputRef {
    pub uri: String,
    pub format: String,
}

starlark_simple_value!(OutputRef);

#[starlark_value(type = "Output")]
impl<'v> StarlarkValue<'v> for OutputRef {}

impl Display for OutputRef {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "<Output uri={} format={}>", self.uri, self.format)
    }
}

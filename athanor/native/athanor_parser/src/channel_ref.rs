use allocative::Allocative;
use starlark::any::ProvidesStaticType;
use starlark::starlark_simple_value;
use starlark::values::{starlark_value, NoSerialize, StarlarkValue};
use std::fmt::{Display, Formatter};

#[derive(Debug, Clone, ProvidesStaticType, NoSerialize, Allocative)]
pub struct ChannelRef {
    pub id: String,
}

starlark_simple_value!(ChannelRef);

#[starlark_value(type = "Channel")]
impl<'v> StarlarkValue<'v> for ChannelRef {}

impl Display for ChannelRef {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "<Channel {}>", self.id)
    }
}

defmodule Co2reader.Devices.TFADostmann do

  defstruct [hid: nil, hid_info: nil]

  def new(hid_device) do
    %__MODULE__{hid_info: hid_device}
  end
end

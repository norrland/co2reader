defmodule Co2reader do
  @moduledoc """
  Documentation for `Co2reader`.
  """

  require Logger

  @vendor_id 1241
  @product_id 41042

  @random_key [0xc4, 0xc6, 0xc0, 0x92, 0x40, 0x23, 0xdc, 0x96]

  def open(vendor_id \\ @vendor_id, product_id \\ @product_id) do
    {:ok, ref} = HID.open(vendor_id, product_id)
    ref
  end

  def read(device, size \\ 9) do
    {:ok, data} = HID.read(device, size)
    data
  end

  # Data takes a key used for encryption, use a default static key
  def set_report(device, key \\ @random_key) when is_list(key) do
    # prepend with 0x00
    {:ok, _bytes} = HID.write_report(device, [0x00 | key])
  end

  def decrypt(data, key \\ @random_key) do
    cstate = [0x48,  0x74,  0x65,  0x6D,  0x70,  0x39,  0x39,  0x65]
    shuffle = [2, 4, 0, 7, 1, 6, 5, 3]

    data = :binary.bin_to_list(data)
           |> IO.inspect(label: "data list")

    ctmp = prepare_ctmp(cstate)

    shuffle
    |> Enum.zip(data)
    |> List.keysort(0)
    |> Enum.map(fn {_pos, value} -> value end)
    |> IO.inspect(label: "phase1, shuffle")
    |> Enum.zip(key) # Prepare for phase2
    |> Enum.map(fn {p1, k} -> Bitwise.bxor(p1,k) end)
    |> IO.inspect(label: "phase2, XOR")
    |> phase3
    |> IO.inspect(label: "phase3, yep..")
    |> calc_values(ctmp)
    |> IO.inspect(label: "final values")
  end

  defp phase3(list) do
    phase2 = list
    phase2b_order = for i <- 0..7, do: rem(i-1+8,8)

    phase2b = for j <- phase2b_order, do: Enum.at(phase2, j)

    Enum.zip(phase2, phase2b)
    |> Enum.map(fn {p2, p2b} ->
      Bitwise.bor(
        Bitwise.bsr(p2, 3),
        Bitwise.bsl(p2b, 5)
      )
       |> Bitwise.band(0xff)
      end
    )
  end

  defp prepare_ctmp(cstate) do
    for i <- 0..7, do:
    Bitwise.bor(
      Bitwise.bsr(Enum.at(cstate, i), 4),
      Bitwise.bsl(Enum.at(cstate, i), 4)
    )
      |> Bitwise.band(0xff)
  end

  defp calc_values(phase3, ctmp) do
    for i <- 0..7, do:
      (0x100 + Enum.at(phase3, i) - Enum.at(ctmp, i))
      |> Bitwise.band(0xff)
  end

  def checksum_valid?(data) when is_bitstring(data) do
    :binary.bin_to_list(data)
    |> checksum_valid?
  end

  def checksum_valid?(data) when is_list(data) do
    data
    |> Enum.at(4) == 0x0d and
    (
      (Enum.take(data, 3)
        |> Enum.reduce(fn x,acc -> x+acc end)
        |> Bitwise.band(0xff))
      |> Kernel.==(Enum.at(data, 3))
    )
  end

  def parse_data(data) when is_bitstring(data) do
    data
    |> :binary.bin_to_list
    |> parse_data
  end

  def parse_data(data) when is_list(data) do
    Logger.debug("data: #{inspect(data)}")
    identifier = Enum.at(data, 0)
    value = Bitwise.bor(
      Bitwise.bsl(
        Enum.at(data, 1), 8),
        Enum.at(data, 2)
      )

    Logger.debug("ID: #{identifier} - #{value}")
    case {identifier, value} do
      {0x53, val} -> %{unknown: val}
      {0x50, val} -> %{co2: val}
      {0x42, val} -> %{temp: val/16.0-273.15 |> Float.round(2)}
      {0x44, val} -> %{rh: val/100.0 |> Float.round(2)}
      {0x41, val} -> %{rh: val/100.0 |> Float.round(2)}
    end
  end

end

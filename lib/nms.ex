defmodule Nms do
  @moduledoc """
  Non Maximum Suppression (experimental)
  """
  
  # candidate features 
  defstruct score: 0.0, box: [0.0, 0.0, 1.0, 1.0], area: 1.0

  ##############################################################################
  # parameter file loader
  ##############################################################################
  @doc """
  load a table with applying the option.
  [option] format:     formatter function for input.
           transposed: transpose the table if it is true.
  """
  def load_table(fname, opts \\ []) do
    formatter   = Keyword.get(opts, :format, &String.trim/1)
    transposed? = Keyword.get(opts, :transposed, false)

    try do
      { :ok,
        File.stream!(fname)
          |> Enum.map(formatter)
          |> (if transposed?, do: &transposed/1, else: &(&1)).()}
    rescue
      File.Error -> {:error, fname}
    end
  end

  @doc """
  formatter: convert white-spase separated text to the list of float.
  it allows the string representation of an integer.
  """
  def float_list(line) do
    String.split(line) |> Enum.map(&elem(Float.parse(&1), 0))
  end

  @doc """
  formatter: convert text to the atom.
  """
  def to_atom(line) do
    String.trim(line) |> String.to_atom
  end

  @doc """
  get the transposed table.
  """
  def transposed(mat) do
    Enum.zip(mat) |> Enum.map(&Tuple.to_list/1)
  end

  ##############################################################################
  # output result
  ##############################################################################
  @doc """
  put the nms result to the device.
  """
  def puts_boxes(device, {class, boxes}) do
    IO.puts(device, "#{class}:")
    Enum.each(boxes, fn %Nms{box: [x1,y1,x2,y2]} ->
      IO.puts(device, "#{x1} #{y1} #{x2} #{y2}")
    end)
  end

  ##############################################################################
  # Multi Non Maximum Suppression
  ##############################################################################
  @doc """
  run non-maximum-suppression on all classes.
  """
  def multi_non_maximum_suppression(classes, scores, boxes, threshold \\ 0.0, iou_threshold \\ 1.0) do
    areas = Enum.map(boxes, fn [x1,y1,x2,y2] -> (x2-x1)*(y2-y1) end)  # pre-calculation for efficiency.

    Enum.zip(classes, scores)
    |> Enum.map(&non_maximum_suppression(&1, boxes, areas, threshold, iou_threshold))
    |> Enum.filter(&(&1)) # remove nil
  end

  @doc """
  execute non-maximum-suppression for a given class.
  """
  def non_maximum_suppression({class, scores}, boxes, areas, threshold \\ 0.0, iou_threshold \\ 1.0) do
    # make a list of candidates in ascending order of their scores,
    # and remove those whose scores are less than the threshold.
    candidates =
      Enum.zip([scores, boxes, areas])
      |> Enum.filter(fn {score, _, _} -> score > threshold end)
      |> Enum.map(fn {score, box, area} -> %Nms{score: score, box: box, area: area} end)
      |> Enum.sort(&(&1.score >= &2.score))

    if candidates != [], do: {class, hard_nms_loop(candidates, iou_threshold, [])}
  end

  defp hard_nms_loop([], _iou_threshold, result) do
    # exsit condition
    result
  end
  defp hard_nms_loop([highest|rest], iou_threshold, result) do
    # update the list by removing candidates whose iou is greater than the iou_threshold.
    candidates =
      Enum.map(rest, &if(iou(&1, highest) < iou_threshold, do: &1))
      |> Enum.filter(&(&1)) # remove nil

    # and repeat again.
    hard_nms_loop(candidates, iou_threshold, [highest|result])
  end

  @doc """
  Intersection over Union
  calculate the iou of the highest box (a) and the other one (b).
  """
  def iou(%Nms{box: [bx1,by1,bx2,by2], area: barea}, %Nms{box: [ax1,ay1,ax2,ay2], area: aarea}) do
    x1 = if bx1 > ax1, do: bx1, else: ax1  # max
    y1 = if by1 > ay1, do: by1, else: ay1  # max
    x2 = if bx2 < ax2, do: bx2, else: ax2  # min
    y2 = if by2 < ay2, do: by2, else: ay2  # min

    if x1 < x2 && y1 < y2 do
      intersection = (x2-x1)*(y2-y1)
      union        = aarea + barea - intersection
      intersection/(union + 1.0e-5)
    else
      0.0
    end
  end

  ##############################################################################
  # CLI main
  ##############################################################################
  @doc """
  main of command line interface.
  usage: nms [option] <class file> <score file> <box file>
  [option] --score: score threshold (0.0..1.0)
           --iou:   iou threshold (0.0..1.0)
  """
  def main(argv \\ []) do
    {opts, files, _} = OptionParser.parse(argv, strict: [score: :float, iou: :float, output: :string])
    
    threshold     = Keyword.get(opts, :score,  0.0)
    iou_threshold = Keyword.get(opts, :iou,    1.0)
    output        = Keyword.get(opts, :output, "con")   ##[CAUTION!:shoz:20/11/08] windows only

    result = with \
      [class_tbl, score_tbl, box_tbl] <- files,
      {:ok, classes} <- load_table(class_tbl, format: &to_atom/1),
      {:ok, scores } <- load_table(score_tbl, format: &float_list/1, transposed: true),
      {:ok, boxes  } <- load_table(box_tbl,   format: &float_list/1)
    do
      {:ok, multi_non_maximum_suppression(classes, scores, boxes, threshold, iou_threshold)}
    end
    
    with \
      {:ok, predictions} <- result,
      {:ok, file} <- File.open(output, [:write])
    do
      Enum.each(predictions, &puts_boxes(file, &1))
      File.close(file)
    end
  end
end

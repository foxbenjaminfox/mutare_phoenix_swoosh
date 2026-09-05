defmodule Mutare.Phoenix.Swoosh.AST do
  @moduledoc false

  # Shared AST helpers for this package's two families, mirroring `Mutare.Swoosh.AST` in the
  # base package: reading a literal map/keyword container, the pipe-aware "remove this call"
  # replacement, and the rebuild compactor. Every fact both families need lives here once.

  alias Mutare.AST
  alias Mutare.CallRouting.Call
  alias Mutare.Mutator

  @typedoc """
  A literal `%{...}` or `[key: value]` argument, read as its entry list plus the function that
  puts a new entry list back into the same container shape.
  """
  @type container :: {:keyword | :map, [Macro.t()], ([Macro.t()] -> Macro.t())}

  # The call's effective argument `index` as `{visible_index, node}` — the visible index is what
  # `List.replace_at/3` needs, and it shifts under a pipe.
  @spec effective_arg(Call.t(), non_neg_integer()) :: {non_neg_integer(), Macro.t()} | nil
  def effective_arg(%Call{arguments: args, pipe_mode: pipe_mode}, effective_index) do
    index = Mutator.visible_index(effective_index, pipe_mode)

    case Enum.at(args, index) do
      nil -> nil
      node -> {index, node}
    end
  end

  @spec container(Macro.t()) :: {:ok, container()} | :error
  def container(node) do
    case keyword_container(node) do
      {:ok, container} -> {:ok, container}
      :error -> map_container(node)
    end
  end

  @spec keyword_container(Macro.t()) :: {:ok, container()} | :error
  def keyword_container(node) do
    with {:ok, entries, wrap} <- list_container(node),
         true <- entries != [] and Enum.all?(entries, &keyword_entry?/1) do
      {:ok, {:keyword, entries, wrap}}
    else
      _other -> :error
    end
  end

  @spec map_container(Macro.t()) :: {:ok, container()} | :error
  def map_container({:%{}, meta, entries}) when is_list(entries) do
    if Enum.all?(entries, &pair?/1),
      do: {:ok, {:map, entries, fn new_entries -> {:%{}, meta, new_entries} end}},
      else: :error
  end

  def map_container(_node), do: :error

  @spec list_container(Macro.t()) :: {:ok, [Macro.t()], ([Macro.t()] -> Macro.t())} | :error
  def list_container({:__block__, meta, [items]}) when is_list(items),
    do: {:ok, items, fn new_items -> {:__block__, meta, [new_items]} end}

  def list_container(items) when is_list(items), do: {:ok, items, & &1}
  def list_container(_node), do: :error

  @spec pair?(Macro.t()) :: boolean()
  def pair?({_key, _value}), do: true
  def pair?(_entry), do: false

  # The entry's key as an atom (`nil` for a string-keyed or computed key).
  @spec key(Macro.t()) :: atom() | nil
  def key({key, _value}), do: AST.key_atom(key)
  def key(_entry), do: nil

  # The entry's key as its literal value, whatever its type (`"html"`, `:layout`).
  @spec literal_key(Macro.t()) :: {:ok, term()} | :error
  def literal_key({key, _value}), do: AST.literal_value(key)
  def literal_key(_entry), do: :error

  @spec replace_value(Macro.t(), Macro.t()) :: Macro.t()
  def replace_value({key, _value}, new_value), do: {key, new_value}

  @spec entry(atom(), term()) :: Macro.t()
  def entry(key, value) when is_atom(key), do: {AST.keyword_key(key), AST.literal(value)}

  # Append one argument to a call node, in whatever form it was written. `Call.rebuild` cannot
  # be used for this: it requalifies a bare imported call when the replacement changes arity,
  # and a requalified `Phoenix.Swoosh.render_body/3` is *not* the `use`-injected local wrapper
  # the source called — it skips the wrapper's `put_new_view`, so the mutant would die as a
  # "view module was not specified" crash instead of testing the layout.
  @spec append_argument(Macro.t(), Macro.t()) :: Macro.t() | nil
  def append_argument({form, meta, args}, argument) when is_list(args),
    do: {form, meta, args ++ [argument]}

  def append_argument(_node, _argument), do: nil

  @spec map([Macro.t()]) :: Macro.t()
  def map(entries) when is_list(entries), do: {:%{}, [], entries}

  @spec empty_map() :: Macro.t()
  def empty_map, do: map([])

  @spec false_literal?(Macro.t()) :: boolean()
  def false_literal?(node), do: AST.literal_value(node) == {:ok, false}

  # The pipe-aware "remove this call, keep the email" replacement: a direct call collapses to its
  # first argument; a piped stage becomes `Elixir.Function.identity()` (absolute, so no alias in
  # the target source can redirect it).
  @spec collapse_to_email(Call.t()) :: Macro.t()
  def collapse_to_email(%Call{pipe_mode: :piped}),
    do: AST.absolute_call([:Function], :identity, [])

  def collapse_to_email(%Call{pipe_mode: :unpiped, arguments: [email | _rest]}), do: email

  # `Call.rebuild` reuses the visible argument nodes, whose meta still describes the original
  # source layout; mixed with a fresh, position-free node, Sourceror renders the rebuild across
  # several lines. Dropping the position keys from the rebuilt subtree renders the mutant
  # compactly; the value-shaping keys (`:delimiter`, `:format`, `:token`) stay.
  @position_keys [:line, :column, :end_of_expression, :newlines, :closing]

  @spec compact(Macro.t()) :: Macro.t()
  def compact(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, Keyword.drop(meta, @position_keys), args}
      other -> other
    end)
  end

  defp keyword_entry?({key, _value}), do: AST.keyword_label?(key)
  defp keyword_entry?(_entry), do: false
end

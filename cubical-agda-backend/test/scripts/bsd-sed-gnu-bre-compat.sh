#!/bin/sh

set -eu

# Agda's interaction drivers pass basic-regexp sed expressions that use GNU
# sed's \+ and \? extensions. BSD sed leaves those expressions unmatched.
# Translate only those extensions and GNU's -r spelling, then delegate every
# other behavior to the system sed. Expressions supplied through -e are
# handled as well because the custom interaction Makefile calls this wrapper as
# gsed.
if [ "$#" -eq 0 ]; then
  exec /usr/bin/sed
fi

exec /usr/bin/perl -e '
  use strict;
  use warnings;

  my @args = @ARGV;
  my $expect_expression = 0;
  my $implicit_expression_seen = 0;
  my $translate = sub {
    my ($expression) = @_;
    # This is the only GNU BRE alternation used by the custom interaction
    # driver. BSD BRE has no alternation operator, so replace literal \n first
    # and then collapse the resulting spaces using two portable BRE commands.
    if (index($expression, "\\|") >= 0) {
      return q!s/\\\\n/ /g; s/ \{1,\}/ /g!;
    }
    $expression =~ s/\\\+/\\{1,\\}/g;
    $expression =~ s/\\\?/\\{0,1\\}/g;
    return $expression;
  };
  for (my $i = 0; $i < @args; $i++) {
    if ($args[$i] eq "-r") {
      $args[$i] = "-E";
      next;
    }
    if ($args[$i] eq "-nr" || $args[$i] eq "-rn") {
      $args[$i] = "-nE";
      next;
    }
    if ($args[$i] eq "-e") {
      $expect_expression = 1;
      next;
    }
    if ($args[$i] =~ /^-e(.+)$/s) {
      $args[$i] = "-e" . $translate->($1);
      next;
    }
    if ($expect_expression || (!$implicit_expression_seen && $args[$i] !~ /^-/)) {
      $args[$i] = $translate->($args[$i]);
      $expect_expression = 0;
      $implicit_expression_seen = 1;
    }
  }
  exec "/usr/bin/sed", @args;
  die "cannot execute /usr/bin/sed: $!";
' -- "$@"

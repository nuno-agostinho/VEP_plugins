=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2021] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

 Ensembl <http://www.ensembl.org/info/about/contact/index.html>

=cut

=head1 NAME

 REVEL

=head1 SYNOPSIS

 mv REVEL.pm ~/.vep/Plugins
 ./vep -i variations.vcf --plugin REVEL,/path/to/revel/data.tsv.gz

=head1 DESCRIPTION

 This is a plugin for the Ensembl Variant Effect Predictor (VEP) that
 adds the REVEL score for missense variants to VEP output.

 Please cite the REVEL publication alongside the VEP if you use this resource:
 https://www.ncbi.nlm.nih.gov/pubmed/27666373
 
 REVEL scores can be downloaded from: https://sites.google.com/site/revelgenomics/downloads
 and can be tabix-processed by:
 
 cat revel_all_chromosomes.csv | tr "," "\t" > tabbed_revel.tsv
 sed '1s/.*/#&/' tabbed_revel.tsv > new_tabbed_revel.tsv
 bgzip new_tabbed_revel.tsv

 for GRCh37:
 tabix -f -s 1 -b 2 -e 2 new_tabbed_revel.tsv.gz

 for GRCh38:
 zcat new_tabbed_revel.tsv.gz | head -n1 > h
 zgrep -h -v ^#chr new_tabbed_revel.tsv.gz | awk '$3 != "." ' | sort -k1,1 -k3,3n - | cat h - | bgzip -c > new_tabbed_revel_grch38.tsv.gz
 tabix -f -s 1 -b 3 -e 3 new_tabbed_revel_grch38.tsv.gz

 The tabix utility must be installed in your path to use this plugin.

=cut

package REVEL;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Sequence qw(reverse_comp);

use Bio::EnsEMBL::Variation::Utils::BaseVepTabixPlugin;

use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepTabixPlugin);

sub new {
  my $class = shift;

  my $self = $class->SUPER::new(@_);

  $self->expand_left(0);
  $self->expand_right(0);

  $self->get_user_params();

 # get headers
  my $file = $self->params->[0];
  open HEAD, "tabix -fh $file 1:1-1 2>&1 | ";
  while(<HEAD>) {
    next unless /^\#/;
    chomp;
    $_ =~ s/^\#//;
    $self->{headers} = [split];
  }
  close HEAD;

  die "ERROR: Could not read headers from $file\n" unless defined($self->{headers}) && scalar @{$self->{headers}};
  my $column_count = scalar @{$self->{headers}};
  if ($column_count != 7 && $column_count != 8) {
    die "ERROR: Column count must be 8 for REVEL files with GRCh38 positions or 7 for REVEL files with GRCh37 positions only.\n";
  }

  $self->{revel_file_columns} = $column_count;

  return $self;
}

sub feature_types {
  return ['Transcript'];
}

sub get_header_info {
  return { REVEL => 'Rare Exome Variant Ensemble Learner '};
}

sub run {
  my ($self, $tva) = @_;
  # only for missense variants
  return {} unless grep {$_->SO_term eq 'missense_variant'} @{$tva->get_all_OverlapConsequences};

  my $assembly = $self->{config}->{assembly};
  my ($start_key, $end_key) = ('start_grch38', 'end_grch38');
  if ($assembly eq 'GRCh37') {
    ($start_key, $end_key) = ('start_grch37', 'end_grch37');
  }
  my $vf = $tva->variation_feature;
  my $allele = $tva->variation_feature_seq;

  my ($res) = grep {
    $_->{alt}        eq $allele &&
    $_->{$start_key} eq $vf->{start} &&
    $_->{$end_key}   eq $vf->{end} &&
    $_->{altaa}      eq $tva->peptide
  } @{$self->get_data($vf->{chr}, $vf->{start}, $vf->{end})};

  return $res ? $res->{result} : {};
}

sub parse_data {
  my ($self, $line) = @_;

  my @values = split /\t/, $line;
  # the lastest version also contains GRCh38 coordinates
  if ($self->{revel_file_columns} == 8) {
    my ($c, $s_grch37, $s_grch38, $ref, $alt, $refaa, $altaa, $revel_value) = @values;

    return {
      alt => $alt,
      start_grch37 => $s_grch37,
      end_grch37 => $s_grch37,
      start_grch38 => $s_grch38,
      end_grch38 => $s_grch38,
      altaa => $altaa,
      result => {
        REVEL   => $revel_value,
      }
    };
  } 
  # the first version only has GRCh37 coordinates
  elsif ($self->{revel_file_columns} == 7) {
    my ($c, $s, $ref, $alt, $refaa, $altaa, $revel_value) = @values;

    return {
      alt => $alt,
      start_grch37 => $s,
      end_grch37 => $s,
      altaa => $altaa,
      result => {
        REVEL   => $revel_value,
      }
    };
  } else {
    return;
  }
}

sub get_start {
  return $_[1]->{start};
}

sub get_end {
  return $_[1]->{end};
}

1;

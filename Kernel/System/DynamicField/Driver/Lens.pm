# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2023 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::System::DynamicField::Driver::Lens;

## nofilter(TidyAll::Plugin::OTOBO::Perl::ParamObject)

use v5.24;
use strict;
use warnings;
use namespace::autoclean;
use utf8;

use parent qw(Kernel::System::DynamicField::Driver::Base);

# core modules

# CPAN modules

# OTOBO modules
use Kernel::System::VariableCheck qw(IsHashRefWithData IsArrayRefWithData);
use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Log',
    'Kernel::System::Web::Request',
);

=head1 NAME

Kernel::System::DynamicField::Driver::Lens - driver for the Lens dynamic field

=head1 DESCRIPTION

Access to an attribute of a referenced object.

=head1 PUBLIC INTERFACE

This dynamic field driver module implements the public interface of L<Kernel::System::DynamicField::Backend>.
Please look there for a detailed reference of the functions.

=head2 new()

it is usually not necessary to explicitly create instances of dynamic field drivers.
Instances of the drivers are created in the constructor of the
dynamic field backend object C<Kernel::System::DynamicField::Backend>.

=cut

sub new {
    my ($Type) = @_;

    # allocate new hash for object
    my $Self = bless {}, $Type;

    # Used for declaring CSS classes
    $Self->{FieldCSSClass} = 'DynamicFieldLens';

    # set field behaviors
    $Self->{Behaviors} = {
        'IsACLReducible'               => 0,
        'IsNotificationEventCondition' => 1,
        'IsSortable'                   => 1,
        'IsFiltrable'                  => 0,
        'IsStatsCondition'             => 1,
        'IsCustomerInterfaceCapable'   => 0,
        'IsHiddenInTicketInformation'  => 0,
    };

    return $Self;
}

sub ValueGet {
    my ( $Self, %Param ) = @_;

    my $LensDFConfig = $Param{DynamicFieldConfig};

    my $ReferencedObjectID = $Self->_GetReferencedObjectID(
        ObjectID               => $Param{ObjectID},
        LensDynamicFieldConfig => $LensDFConfig,
        EditFieldValue         => $Param{UseReferenceEditField},
    );

    return unless ref $ReferencedObjectID;
    return unless $ReferencedObjectID->@*;

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $LensDFConfig,
    );

    # Lenses return at most one value, so we don't have to loop here.
    my $BackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my @Values        = map {
        $BackendObject->ValueGet(
            DynamicFieldConfig => $AttributeDFConfig,
            ObjectID           => $_,
        );
    } $ReferencedObjectID->@*;

    # TODO: for now return a non-nested list, but that does not work for all values
    #       This might fail for text fields.
    return [ map { ref $_ ? $_->@* : $_ } @Values ];
}

sub ValueSet {
    my ( $Self, %Param ) = @_;

    my $LensDFConfig = $Param{DynamicFieldConfig};

    # as we are already saving we trust, that the reference edit field has been validated
    my $ReferencedObjectID = $Self->_GetReferencedObjectID(
        ObjectID               => $Param{ObjectID},
        LensDynamicFieldConfig => $LensDFConfig,
        EditFieldValue         => 1,
    );

    # TODO: Do we want to log this?
    return unless ref $ReferencedObjectID;
    return unless $ReferencedObjectID->@*;

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $LensDFConfig,
    );

    my $ReferenceDFConfig = $Self->_GetReferenceDFConfig(
        LensDynamicFieldConfig => $LensDFConfig,
    );

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ValueSet(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
        ObjectID           => $ReferencedObjectID->[0],
        ObjectType         => $ReferenceDFConfig->{Config}->{ReferencedObjectType},
    );
}

sub ValueValidate {
    my ( $Self, %Param ) = @_;

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $Param{DynamicFieldConfig},
    );

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ValueValidate(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
    );
}

sub SearchSQLGet {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    if ( $Param{Operator} eq 'Like' ) {

        # TODO: also search ConfigItemID when an integer is given
        return $DBObject->QueryCondition(
            Key   => "$Param{TableAlias}.value_text",
            Value => $Param{SearchTerm},
        );
    }

    # TODO: should other operators be supported ??
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        'Priority' => 'error',
        'Message'  => "Unsupported Operator $Param{Operator}",
    );

    return;
}

sub SearchSQLOrderFieldGet {
    my ( $Self, %Param ) = @_;

    # TODO
    return '';
}

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    my $LensDFConfig = $Param{DynamicFieldConfig};

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $LensDFConfig,
    );

    # The edit field should be rendered like the attribute of the referenced object,
    # But name and Label should be that of the Lens dynamic field.
    $AttributeDFConfig->{Name}  = $LensDFConfig->{Name};
    $AttributeDFConfig->{Label} = $LensDFConfig->{Label};
    my $AttributeFieldHTML = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->EditFieldRender(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
    );

    return $AttributeFieldHTML;
}

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $LensDFConfig = $Param{DynamicFieldConfig};

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $LensDFConfig,
    );

    # The name used in the GUI is the name of the Lens
    $AttributeDFConfig->{Name} = $LensDFConfig->{Name};

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->EditFieldValueGet(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
    );
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # TODO please implement

    # create resulting structure
    return {
        ServerError  => undef,
        ErrorMessage => undef,
    };
}

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    my $LensDFConfig = $Param{DynamicFieldConfig};

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $LensDFConfig,
    );

    return '' unless $AttributeDFConfig;

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->DisplayValueRender(
        %Param,    # e.g. Value and HTMLOutput
        DynamicFieldConfig => $AttributeDFConfig,
    );
}

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    # set the field value
    my $Value = $Param{DefaultValue} // '';

    # get the field value, this function is always called after the profile is loaded
    my $FieldValue = $Self->SearchFieldValueGet(%Param);

    # set values from profile if present
    if ( defined $FieldValue ) {
        $Value = $FieldValue;
    }

    # check if value is an array reference (GenericAgent Jobs and NotificationEvents)
    if ( IsArrayRefWithData($Value) ) {
        $Value = @{$Value}[0];
    }

    # check and set class if necessary
    my $FieldClass = $Self->{FieldCSSClass};    # for field specific JS

    my $ValueEscaped = $Param{LayoutObject}->Ascii2Html(
        Text => $Value,
    );

    my $FieldLabelEscaped = $Param{LayoutObject}->Ascii2Html(
        Text => $FieldLabel,
    );

    my $HTMLString = <<"EOF";
<input type="text" class="$FieldClass" id="$FieldName" name="$FieldName" title="$FieldLabelEscaped" value="$ValueEscaped" />
EOF

    my $AdditionalText;
    if ( $Param{UseLabelHints} ) {
        $AdditionalText = Translatable('e.g. Text or Te*t');
    }

    # call EditLabelRender on the common Driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        FieldName      => $FieldName,
        AdditionalText => $AdditionalText,
    );

    return {
        Field => $HTMLString,
        Label => $LabelString,
    };
}

sub SearchFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $Value;

    # get dynamic field value from param object
    if ( defined $Param{ParamObject} ) {
        $Value = $Param{ParamObject}->GetParam(
            Param => 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name}
        );
    }

    # otherwise get the value from the profile
    elsif ( defined $Param{Profile} ) {
        $Value = $Param{Profile}->{ 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} };
    }
    else {
        return;
    }

    if ( defined $Param{ReturnProfileStructure} && $Param{ReturnProfileStructure} eq 1 ) {
        return {
            'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} => $Value,
        };
    }

    return $Value;
}

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # get field value
    my $Value = $Self->SearchFieldValueGet(%Param);

    # set operator
    my $Operator = 'Equals';

    # search for a wild card in the value
    if ( $Value && ( $Value =~ m{\*} || $Value =~ m{\|\|} ) ) {

        # change operator
        $Operator = 'Like';
    }

    # return search parameter structure
    return {
        Parameter => {
            $Operator => $Value,
        },
        Display => $Value,
    };
}

sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    return {
        Name    => $Param{DynamicFieldConfig}->{Label},
        Element => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
    };
}

sub StatsSearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $Value = $Param{Value};

    # set operator
    my $Operator = 'Equals';

    # search for a wild card in the value
    if ( $Value && $Value =~ m{\*} ) {

        # change operator
        $Operator = 'Like';
    }

    return {
        $Operator => $Value,
    };
}

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    my $Value = '';

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    # set new line separator
    my $ItemSeparator = ', ';

    # Output transformations
    $Value = join( $ItemSeparator, @Values );
    my $Title = $Value;

    # cut strings if needed
    if ( $Param{ValueMaxChars} && length($Value) > $Param{ValueMaxChars} ) {
        $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
    }
    if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
        $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
    }

    # return a data structure
    return {
        Value => $Value,
        Title => $Title,
    };
}

sub TemplateValueTypeGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # set the field types
    my $EditValueType   = 'SCALAR';
    my $SearchValueType = 'SCALAR';

    # return the correct structure
    if ( $Param{FieldType} eq 'Edit' ) {
        return {
            $FieldName => $EditValueType,
        };
    }
    elsif ( $Param{FieldType} eq 'Search' ) {
        return {
            'Search_' . $FieldName => $SearchValueType,
        };
    }
    else {
        return {
            $FieldName             => $EditValueType,
            'Search_' . $FieldName => $SearchValueType,
        };
    }
}

sub RandomValueSet {
    my ( $Self, %Param ) = @_;

    # do nothing but reporting success

    return {
        Success => 1,
        Value   => 1,
    };
}

sub ObjectMatch {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # return false if field is not defined
    return 0 unless defined $Param{ObjectAttributes}->{$FieldName};

    # return false if not match
    return 1 if $Param{ObjectAttributes}->{$FieldName} eq $Param{Value};
    return 0;
}

sub HistoricalValuesGet {
    my ( $Self, %Param ) = @_;

    # return the historical values from database
    return $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->HistoricalValueGet(
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text',
    );
}

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $Param{DynamicFieldConfig},
    );

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ValueLookup(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
    );
}

sub ValueIsDifferent {
    my ( $Self, %Param ) = @_;

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $Param{DynamicFieldConfig},
    );

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ValueIsDifferent(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
    );
}

sub HasBehavior {
    my ( $Self, %Param ) = @_;

    # TODO: Think about additional behaviors we can just adopt from the attribute field
    # for certain behaviors instead use the attribute field behaviors
    if ( grep { $Param{Behavior} } qw/IsACLReducible/ ) {
        my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
            LensDynamicFieldConfig => $Param{DynamicFieldConfig},
        );

        return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->HasBehavior(
            %Param,
            DynamicFieldConfig => $AttributeDFConfig,
        );
    }

    # return success if the dynamic field has the expected behavior
    return IsPositiveInteger( $Self->{Behaviors}->{ $Param{Behavior} } );
}

sub PossibleValuesGet {
    my ( $Self, %Param ) = @_;

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $Param{DynamicFieldConfig},
    );

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->PossibleValuesGet(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
    );
}

sub BuildSelectionDataGet {
    my ( $Self, %Param ) = @_;

    my $AttributeDFConfig = $Self->_GetAttributeDFConfig(
        LensDynamicFieldConfig => $Param{DynamicFieldConfig},
    );

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->BuildSelectionDataGet(
        %Param,
        DynamicFieldConfig => $AttributeDFConfig,
    );
}

=head1 internal methods

Methods that are used only internally.

=head2 _GetReferenceDFConfig()

A dynamic field configuration that can be used as a delegate.

=cut

#TODO: in CI definitions store the definition id or df configs in the lens config and use this one instead of the current df configs
sub _GetReferenceDFConfig {
    my ( $Self, %Param ) = @_;

    $Self->{ReferenceDFCache}{ $Param{LensDynamicFieldConfig}{ID} } //= $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
        ID => $Param{LensDynamicFieldConfig}{Config}{ReferenceDF},
    );

    return $Self->{ReferenceDFCache}{ $Param{LensDynamicFieldConfig}{ID} };
}

=head2 _GetAttributeDFConfig()

A dynamic field configuration that can be used as a delegate.

=cut

sub _GetAttributeDFConfig {
    my ( $Self, %Param ) = @_;

    if ( !defined $Self->{AttributeDFCache}{ $Param{LensDynamicFieldConfig}{ID} } ) {
        my $DynamicFieldConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
            ID => $Param{LensDynamicFieldConfig}{Config}{AttributeDF},
        );
        $Self->{AttributeDFCache}{ $Param{LensDynamicFieldConfig}{ID} } = $DynamicFieldConfig ? { $DynamicFieldConfig->%* } : {};
    }

    return $Self->{AttributeDFCache}{ $Param{LensDynamicFieldConfig}{ID} };
}

=head2 _GetReferencedObjectID()

The config of the lens contains the ID of another dynamic field. That field is a Reference dynamic field that
references another object. The ID of the referenced object is the value of the Reference dynamic field.

=cut

sub _GetReferencedObjectID {
    my ( $Self, %Param ) = @_;

    # extract params
    my $LensDFConfig = $Param{LensDynamicFieldConfig};

    # Get the dynamic field config for the referenced object
    my $ReferenceDFConfig = $Self->_GetReferenceDFConfig(
        LensDynamicFieldConfig => $LensDFConfig,
    );

    if ( $Param{EditFieldValue} ) {
        return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->EditFieldValueGet(
            DynamicFieldConfig => $ReferenceDFConfig,
            ParamObject        => $Kernel::OM->Get('Kernel::System::Web::Request'),
            TransformDates     => 0,
            ForLens            => 1,
        );
    }

    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ValueGet(
        DynamicFieldConfig => $ReferenceDFConfig,
        ObjectID           => $Param{ObjectID},
        ForLens            => 1,
    );
}

1;